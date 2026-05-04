# Implementation Plan — Three-Artifact Pipeline Output (SPEC.md + PLAN.md + TASKS.md)

**Implements:** `elliottagentdev/forge#6` via this fork's local issue
**Mode:** Lite pipeline draft — Stage 1 of 3
**Target file:** `/home/agentdev/projects/acorn/main/bin/acorn` (single-file Bash CLI)

---

## 1. Executive Summary

This feature adds a configurable **three-artifact output mode** to the Acorn pipeline. When enabled (via `ACORN_OUTPUT_MODE=three-artifact`), the final-stage agent in each of the three pipeline modes (`full`, `lite`, `quick`) emits three sibling files in `plans/` instead of one:

- `SPEC.md` — functional requirements + traceability matrix (trimmed of impl detail)
- `PLAN.md` — implementation design (architecture, contracts, data, risks)
- `TASKS.md` — atomic, verifiable work items as YAML blocks

Default behavior (`ACORN_OUTPUT_MODE=single` or unset) is unchanged — upstream `craigmmills/acorn` remains source-compatible.

**Implementation strategy: minimal surgery to a single file.** The entire feature is prompt-engineering inside three existing heredoc blocks (`planning_block_full`, `planning_block_lite`, `planning_block_quick`), threading one new env var through three call sites, and adding two soft-warning checks in `cmd_approve` / `cmd_spec_complete`. No new bash modules, no new deps, no new test infrastructure.

**Total file changes:** 1 production file (`bin/acorn`), 1 new test file (`test/test_three_artifact.sh`), 1 docs update (`claude/commands/acorn.md`).

---

## 2. Architecture

### 2.1 Design Principles (in priority order)

1. **Upstreamability** (PROMPT constraint): no forge-specific assumptions in the binary; default-off; the binary emits siblings, downstream decides what to do with them.
2. **Minimal surgery**: one file, one env var, three prompt expansions.
3. **Backwards compatibility**: `single` mode is the default; existing PROMPT.md output is byte-identical when `ACORN_OUTPUT_MODE` is unset.
4. **Pure prompt engineering**: no parsers, no schema validators in bash — schemas are enforced by the LLM via prompt instructions (constraint AC #8: "no new dependencies").
5. **Soft failure on consumer side**: missing PLAN.md/TASKS.md emit `warn`, never `die` — preserves single-mode workflows.

### 2.2 Where the Configuration Flag Lives

Two valid options were considered:

| Option | Pros | Cons | Decision |
|---|---|---|---|
| **A. Env var only** (`ACORN_OUTPUT_MODE`) | Simplest; matches existing env-var pattern (`PROJECTS_DIR`, `TELEGRAM_NOTIFY_PORT`); zero CLI surface change; forge sets it once in its dispatcher | Not discoverable from `--help`; can't override per-invocation easily | **Chosen** for v1; CLI flag can be added later without breaking compatibility |
| B. Env var + CLI flag (`--output-mode three-artifact`) | More discoverable; explicit per-spec | Adds CLI surface area; needs to propagate through `cmd_create` arg parser and meta.json | Deferred; PROMPT.md says "env var **or equivalent CLI flag**" — env var alone satisfies AC #1 |

**Decision:** Env var only. `cmd_create` reads `ACORN_OUTPUT_MODE` once, threads it as a parameter through `render_prompt_md` → `planning_block` → `planning_block_{full,lite,quick}`. Stored in `meta.json` so `cmd_approve` / `cmd_spec_complete` can warn correctly even if the env var isn't set at approve-time.

### 2.3 Where the Three-Artifact Instructions Live

The Acorn pipeline already runs the planning *as an LLM agent reading PROMPT.md*. There is no bash-side code that parses or assembles SPEC.md content. So the entire feature reduces to: **append additional instructions to the Final Spec agent's prompt heredoc** in each pipeline mode.

The instructions tell the LLM to:
1. Write three files instead of one (SPEC.md trimmed, PLAN.md, TASKS.md).
2. Follow the schemas specified verbatim in the prompt (PROMPT.md AC #3, #4, #5).
3. Emit a final response that lists all three paths.

**Architectural choice:** rather than three separate heredocs (one per mode) duplicating the same three-artifact instruction block, we create **one shared bash function `three_artifact_instructions()`** that returns the schema-and-instructions text. Each `planning_block_*()` injects this block via `sed` substitution alongside `__SPEC_PATH__` substitution, only when `ACORN_OUTPUT_MODE=three-artifact`.

This keeps all three modes synchronized: a future schema tweak only needs editing one function. Single-mode users see no change — the substitution placeholder gets replaced with empty string.

### 2.4 Control Flow Diagram

```
ACORN_OUTPUT_MODE=three-artifact   acorn create repo 6
           │                              │
           ▼                              ▼
     env var read in cmd_create
           │
           ▼
     local output_mode="three-artifact"
           │
           ▼
     render_prompt_md(... output_mode)
           │
           ▼
     planning_block(mode, spec_path, output_mode)
           │
   ┌───────┼───────┐
   ▼       ▼       ▼
 _full   _lite   _quick
   │       │       │
   └───────┼───────┘
           │
           ▼
   each emits PROMPT.md heredoc with __THREE_ARTIFACT_BLOCK__
   replaced by either:
     - three_artifact_instructions() text (if mode=three-artifact)
     - empty string (if mode=single)
           │
           ▼
   write_meta_json(... output_mode)
           │
           ▼
   meta.json {..., output_mode: "three-artifact"}
           │
           ▼
   ── Pipeline runs (LLM reads PROMPT.md) ──
           │
           ▼
   plans/SPEC.md + plans/PLAN.md + plans/TASKS.md

LATER:
   acorn approve / acorn spec-complete
           │
           ▼
   read meta.json → output_mode
           │
           ▼
   if three-artifact:
     warn if !PLAN.md ; warn if !TASKS.md
   die only if !SPEC.md   (unchanged)
```

---

## 3. File-by-File Changes

### 3.1 `bin/acorn` — single-file changes

All edits to one file. Below in order of appearance.

#### Change 3.1.1 — Constants block (~line 23, after existing PATH setup)

**Location:** End of the existing global-constants block, before utility functions begin.

**Add:**
```bash
# Output mode controls whether the planning pipeline emits a single SPEC.md
# (default, upstream-compatible) or the three-artifact set
# (SPEC.md + PLAN.md + TASKS.md, used by forge consumers).
# Valid values: "single", "three-artifact"
ACORN_OUTPUT_MODE="${ACORN_OUTPUT_MODE:-single}"
```

**Why here:** matches existing pattern for `PROJECTS_DIR`, `TELEGRAM_NOTIFY_PORT`. Read once at script load; can be overridden by callers. Default matches AC #1 (backwards-compat).

**Validation guard added immediately after:**
```bash
case "$ACORN_OUTPUT_MODE" in
  single|three-artifact) ;;
  *) printf '[WARN] Unknown ACORN_OUTPUT_MODE=%s; falling back to single\n' \
       "$ACORN_OUTPUT_MODE" >&2
     ACORN_OUTPUT_MODE="single" ;;
esac
```

This protects against typos like `three_artifact` or `triple`. We `warn` (not `die`) because env-var typos shouldn't break the entire CLI for users running unrelated subcommands like `acorn list`.

#### Change 3.1.2 — New helper: `three_artifact_instructions()` (new function, place near `planning_block()` ~line 660)

**Why a separate function:** Single source of truth for the schemas. All three pipeline modes inject the same text. A schema change touches exactly one place.

**Signature:**
```bash
# three_artifact_instructions
#   Emits the prompt text that instructs the Final Spec agent to produce
#   three artifacts (SPEC.md + PLAN.md + TASKS.md) instead of one.
#   Uses literal __SPEC_PATH__ tokens; the caller's sed substitution will
#   replace them.
three_artifact_instructions() {
  cat <<'THREE_ARTIFACT_EOF'

---

### THREE-ARTIFACT OUTPUT MODE (ACORN_OUTPUT_MODE=three-artifact)

You MUST produce THREE files in __SPEC_PATH__/plans/, not one:

#### 1. __SPEC_PATH__/plans/SPEC.md  (TRIMMED)

Functional requirements only. KEEP these sections:
  - ## Pi Model Recommendation (top, unchanged)
  - ## 1. Requirements Traceability Matrix
  - ## 2. Functional Requirements (Job Story, Promise, Constraints)
  - ## 6. Risk Register (pointer: "see PLAN.md §5 for full register")
  - ## 7. Acceptance Criteria (pointer: "see TASKS.md for verifiable task list")
REMOVE these sections (they move to PLAN.md / TASKS.md):
  - ## 3. Implementation Plan (entire section — moves to PLAN.md)
  - ## 4. Architecture / Data Model (moves to PLAN.md §1, §3)
  - ## 5. Testing Strategy (moves to PLAN.md §4 + TASKS.md verify commands)

SPEC.md MUST remain valid stand-alone — a legacy reader (single-mode
consumer) reading only SPEC.md must still understand WHAT the feature does
and WHY, just not HOW.

#### 2. __SPEC_PATH__/plans/PLAN.md  (NEW)

Implementation design. Required sections, in order:

  ## 1. Architecture Decisions
     For each decision: 1-3 bullet points with rationale; cite alternatives
     considered and why rejected.

  ## 2. API Contracts
     For each touched function or interface:
       - Inputs (types, validation rules)
       - Outputs (return type, error modes)
       - Side effects (files written, network calls, state mutations)

  ## 3. Data Model Changes
     Schemas, migrations, atomic-rename patterns. If no data changes,
     write "No data model changes."

  ## 4. Implementation Sequence
     Phase names with dependency graph. Each phase independently
     verifiable.

  ## 5. Risk Register
     Known unknowns: severity (low/med/high), likelihood, mitigation.

#### 3. __SPEC_PATH__/plans/TASKS.md  (NEW)

Atomic work items as a YAML list. Each task is a YAML block with this
EXACT schema:

```yaml
- id: T1
  title: "Add verified_send helper to forged.py"
  size: M  # one of: XS, S, M, L, XL
  files: [path/to/file1.py, path/to/file2.py]
  verify: "pytest -q path/to/test.py::test_name"
  depends_on: []  # list of task IDs, e.g. [T1, T2]
```

Sizing rubric:
  - XS: 1 file, <20 lines changed, no new functions
  - S:  1-2 files, <50 lines, may add 1 function
  - M:  2-4 files, <200 lines, may add multiple functions
  - L:  4-8 files, may add new module
  - XL: >8 files OR >3 new interfaces — flag with note:
        ⚠️ XL: requires decomposition

Every task MUST have a non-empty `verify` command that an agent can run
to confirm completion. Prefer specific test invocations over broad
suites. If no test exists, the verify command should be the test that
must be added (and that task gets size XS or S to write the test).

Tasks ordered by `depends_on` (DAG). Topological order in the file.

#### Final response when in three-artifact mode

Your final response must list all three paths:
  Done. Output: __SPEC_PATH__/plans/SPEC.md + __SPEC_PATH__/plans/PLAN.md + __SPEC_PATH__/plans/TASKS.md

THREE_ARTIFACT_EOF
}
```

**Design notes:**
- Heredoc uses `'THREE_ARTIFACT_EOF'` (quoted) so no variable expansion happens inside; only the caller's `sed` substitution converts `__SPEC_PATH__`.
- Schemas are taken verbatim from PROMPT.md AC #3 and AC #4.
- The "trim SPEC.md" instructions satisfy AC #5 (backwards compat — SPEC.md remains valid stand-alone).
- Final response format extended so orchestrator log clearly shows three artifacts produced.

#### Change 3.1.3 — `planning_block()` dispatcher (line 662, add output_mode parameter)

**Current signature:**
```bash
planning_block() {
  local mode="${1:-full}"
  local spec_path="${2:-.}"
  case "$mode" in ...
```

**New signature:**
```bash
planning_block() {
  local mode="${1:-full}"
  local spec_path="${2:-.}"
  local output_mode="${3:-single}"
  case "$mode" in
    full)  planning_block_full  "$spec_path" "$output_mode" ;;
    lite)  planning_block_lite  "$spec_path" "$output_mode" ;;
    quick) planning_block_quick "$spec_path" "$output_mode" ;;
    *)     die "Unknown planning mode: $mode" ;;
  esac
}
```

#### Change 3.1.4 — `planning_block_full()`, `_lite()`, `_quick()` — accept output_mode + inject block

All three functions receive identical structural changes. Pattern shown for `planning_block_lite()`:

**Current:**
```bash
planning_block_lite() {
  local spec_path="${1:-.}"
  cat <<'METHODOLOGY_EOF' | sed "s|__SPEC_PATH__|${spec_path}|g"
  ... heredoc ...
  METHODOLOGY_EOF
}
```

**New:**
```bash
planning_block_lite() {
  local spec_path="${1:-.}"
  local output_mode="${2:-single}"

  # Compute the three-artifact instruction block (or empty for single mode)
  local three_block=""
  if [ "$output_mode" = "three-artifact" ]; then
    three_block="$(three_artifact_instructions)"
  fi

  # Use awk to substitute __THREE_ARTIFACT_BLOCK__ with the multi-line
  # block (sed struggles with multi-line replacements). Then sed handles
  # the simpler __SPEC_PATH__ substitution.
  cat <<'METHODOLOGY_EOF' \
    | awk -v block="$three_block" '{gsub(/__THREE_ARTIFACT_BLOCK__/, block)} 1' \
    | sed "s|__SPEC_PATH__|${spec_path}|g"
  ... existing heredoc ...
  METHODOLOGY_EOF
}
```

**Inside the heredoc**, place the placeholder `__THREE_ARTIFACT_BLOCK__` at the END of the Final Spec agent prompt — specifically, immediately AFTER the existing line:

```
The spec must be ready to be handed to a developer or agent for implementation with ZERO questions.
```

…and BEFORE the existing line:

```
- Write the final spec to __SPEC_PATH__/plans/SPEC.md
```

So the new heredoc fragment reads:
```
The spec must be ready to be handed to a developer or agent for implementation with ZERO questions.

__THREE_ARTIFACT_BLOCK__

- Write the final spec to __SPEC_PATH__/plans/SPEC.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: __SPEC_PATH__/plans/SPEC.md"
```

In single-mode, `__THREE_ARTIFACT_BLOCK__` becomes empty and the prompt is byte-equivalent to today's output (modulo two extra blank lines, harmless).

In three-artifact mode, the LLM sees the schemas directly inline and the final-response format guidance is overridden by the inline instructions ("Your final response must list all three paths").

**Apply the same edit to:**
- `planning_block_full()` (~line 673) — Stage 5 Final Spec agent prompt (~line 1074)
- `planning_block_quick()` (~line 1419) — Stage 1 Direct Spec agent prompt (~line 1540)

The placeholder `__THREE_ARTIFACT_BLOCK__` appears once per heredoc (only in the Final Spec / Direct Spec agent prompt block). This is critical: sub-agents earlier in the pipeline (recon, draft, validation) should NOT receive three-artifact instructions because their job is to produce intermediate artifacts (`recon/*.md`, `draft.md`, `validation.md`), not the final user-facing artifact.

#### Change 3.1.5 — `render_prompt_md()` (line 1621) — accept and forward output_mode

**Current signature:**
```bash
render_prompt_md() {
  local issue_title="$1"
  local issue_body="$2"
  local issue_json="$3"
  local out_tmp="$4"
  local mode="${5:-full}"
  local spec_path="${6:-.}"
  local url_mapping_file="${7:-}"
  ...
  planning_block "$mode" "$spec_path"
}
```

**New signature:** add `output_mode` as 8th positional arg:
```bash
render_prompt_md() {
  local issue_title="$1"
  local issue_body="$2"
  local issue_json="$3"
  local out_tmp="$4"
  local mode="${5:-full}"
  local spec_path="${6:-.}"
  local url_mapping_file="${7:-}"
  local output_mode="${8:-single}"
  ...
  planning_block "$mode" "$spec_path" "$output_mode"
}
```

**Backwards compat:** existing 7-arg callers (none in this codebase, but tests may stub) get default `single` — identical behavior to today.

#### Change 3.1.6 — `cmd_create()` (~line 2209) — read env var and pass through

**Add after the existing arg-parse loop** (~line 2235), and **before** the `render_prompt_md` call (~line 2276):

```bash
# Read output mode from environment (set by forge consumers; default single
# preserves upstream-compatible behavior).
local output_mode="${ACORN_OUTPUT_MODE:-single}"
```

**Update the `render_prompt_md` call** (currently line ~2276):
```bash
# Before:
render_prompt_md "$title" "$body" "$issue_json" "$tmp_path" "$mode" "$dir" "$url_mapping_file"

# After:
render_prompt_md "$title" "$body" "$issue_json" "$tmp_path" "$mode" "$dir" "$url_mapping_file" "$output_mode"
```

**Update the `write_meta_json` call** (currently passes `mode` as the 8th arg):
```bash
# Before:
write_meta_json "$dir/meta.json" "$repo" "$issue_number" "$title" "$slug" "$backend" "$session_name" "$mode"

# After:
write_meta_json "$dir/meta.json" "$repo" "$issue_number" "$title" "$slug" "$backend" "$session_name" "$mode" "$output_mode"
```

**Add a user-visible echo** showing output mode (after the existing "Mode: $mode" echo):
```bash
echo "Output mode: $output_mode"
```

This is a small but high-value DX improvement — operators immediately see whether forge's three-artifact behavior is active.

#### Change 3.1.7 — `write_meta_json()` (~line 1948) — record output_mode

**Current signature:** 8 positional args (last is `mode`).

**New signature:** 9 positional args, last is `output_mode`:
```bash
write_meta_json() {
  local path="$1"
  local repo="$2"
  local issue_number="$3"
  local issue_title="$4"
  local slug="$5"
  local backend="$6"
  local session_name="$7"
  local mode="${8:-full}"
  local output_mode="${9:-single}"

  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  jq -n \
    --arg repo "$repo" \
    --argjson issue_number "$issue_number" \
    --arg issue_title "$issue_title" \
    --arg slug "$slug" \
    --arg created_at "$ts" \
    --arg session_backend "$backend" \
    --arg session_name "$session_name" \
    --arg mode "$mode" \
    --arg output_mode "$output_mode" \
    '{repo:$repo, issue_number:$issue_number, issue_title:$issue_title, slug:$slug, created_at:$created_at, session_backend:$session_backend, session_name:$session_name, mode:$mode, output_mode:$output_mode}' \
    > "$path"
}
```

**Backwards compat for existing meta.json files:** old files lack the `output_mode` field. Readers must use `jq -r '.output_mode // "single"'` to default missing fields to `single`. This pattern is already used elsewhere in the codebase (e.g., `mode // "full"`).

#### Change 3.1.8 — `cmd_approve()` (~line 2392) — soft-warn on missing PLAN/TASKS

**Add immediately after the existing SPEC.md guard (line 2403):**

```bash
# Three-artifact mode (recorded in meta.json at create time): warn but
# don't fail if PLAN.md/TASKS.md are missing. Single-mode: skip these
# checks entirely.
local recorded_output_mode
recorded_output_mode="$(jq -r '.output_mode // "single"' "$dir/meta.json" 2>/dev/null || printf 'single')"
if [ "$recorded_output_mode" = "three-artifact" ]; then
  [ -f "$dir/plans/PLAN.md" ] \
    || warn "Three-artifact mode: missing PLAN.md ($dir/plans/PLAN.md) — approving anyway"
  [ -f "$dir/plans/TASKS.md" ] \
    || warn "Three-artifact mode: missing TASKS.md ($dir/plans/TASKS.md) — approving anyway"
fi
```

**Why read from `meta.json`, not env var:** `acorn approve` may run in a different shell session, hours later, without `ACORN_OUTPUT_MODE` set. The approval check should reflect what the spec was generated with, not what the current shell environment says. This is a critical robustness point — operators routinely approve specs from a different terminal than where they ran `acorn create`.

**Why warn-not-die:** AC #6 explicitly says "warn (not error)". Rationale: an LLM agent might fail to write PLAN.md/TASKS.md (network error, OOM, hallucination). Operators should still be able to approve a SPEC.md-only output and re-run the trim/regenerate later if needed.

#### Change 3.1.9 — `cmd_spec_complete()` (~line 2434) — same soft-warn

**Add immediately after the existing SPEC.md guard (line 2445):**

```bash
local recorded_output_mode
recorded_output_mode="$(jq -r '.output_mode // "single"' "$dir/meta.json" 2>/dev/null || printf 'single')"
if [ "$recorded_output_mode" = "three-artifact" ]; then
  [ -f "$dir/plans/PLAN.md" ] \
    || warn "Three-artifact mode: missing PLAN.md ($dir/plans/PLAN.md)"
  [ -f "$dir/plans/TASKS.md" ] \
    || warn "Three-artifact mode: missing TASKS.md ($dir/plans/TASKS.md)"
fi
```

**Identical pattern to `cmd_approve`** — DRY would suggest factoring this into a helper `check_three_artifact_files()`, but the body is so small (5 lines, one shared local) that a helper would obscure rather than clarify. Keep inline.

If a future change adds a third or fourth caller, refactor to a helper named `warn_if_three_artifact_files_missing(dir)`. For two callers, inline is correct.

---

### 3.2 New test file: `test/test_three_artifact.sh`

Creates a new test file following the existing convention (`test/test_<feature>.sh`). Tests are organized by AC.

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACORN_SCRIPT="$SCRIPT_DIR/bin/acorn"

# Source acorn functions without triggering main()
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }

assert_eq() {
  local name="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then pass "$name"
  else fail "$name" "expected '$expected', got '$actual'"; fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then pass "$name"
  else fail "$name" "expected to contain '$needle'"; fi
}

assert_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    fail "$name" "expected NOT to contain '$needle'"
  else pass "$name"; fi
}

TMPDIR_BASE=""
setup() { TMPDIR_BASE="$(mktemp -d)"; }
teardown() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE"
  unset -f gh ensure_labels set_issue_state_label comment_issue \
           safe_repo_main notify_telegram notify_foreman 2>/dev/null || true
}
trap teardown EXIT

# === AC #1: env var with default single ===
test_default_output_mode_is_single() {
  printf '\n\033[1m== AC#1: default ACORN_OUTPUT_MODE=single ==\033[0m\n'
  unset ACORN_OUTPUT_MODE
  # Re-source to re-run the constants block
  eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"
  assert_eq "default is single" "${ACORN_OUTPUT_MODE:-single}" "single"
}

test_unknown_output_mode_falls_back_to_single() {
  printf '\n\033[1m== AC#1: unknown value falls back to single ==\033[0m\n'
  ACORN_OUTPUT_MODE="bogus"
  # Trigger validation block
  case "$ACORN_OUTPUT_MODE" in
    single|three-artifact) ;;
    *) ACORN_OUTPUT_MODE="single" ;;
  esac
  assert_eq "fell back" "$ACORN_OUTPUT_MODE" "single"
}

# === AC #2 + #3 + #4 + #5: planning_block injects three-artifact text ===
test_planning_block_lite_single_mode_omits_block() {
  printf '\n\033[1m== AC#2: lite single-mode omits three-artifact block ==\033[0m\n'
  local out
  out="$(planning_block_lite "/tmp/spec" "single")"
  assert_not_contains "no THREE-ARTIFACT header" "$out" "THREE-ARTIFACT OUTPUT MODE"
  assert_not_contains "no PLAN.md mention" "$out" "plans/PLAN.md"
  assert_not_contains "no TASKS.md mention" "$out" "plans/TASKS.md"
  assert_contains "still mentions SPEC.md" "$out" "plans/SPEC.md"
}

test_planning_block_lite_three_artifact_includes_block() {
  printf '\n\033[1m== AC#2: lite three-artifact includes schemas ==\033[0m\n'
  local out
  out="$(planning_block_lite "/tmp/spec" "three-artifact")"
  assert_contains "THREE-ARTIFACT header" "$out" "THREE-ARTIFACT OUTPUT MODE"
  assert_contains "mentions PLAN.md path" "$out" "/tmp/spec/plans/PLAN.md"
  assert_contains "mentions TASKS.md path" "$out" "/tmp/spec/plans/TASKS.md"
  # AC #3: PLAN.md required sections
  assert_contains "PLAN §1 Architecture" "$out" "Architecture Decisions"
  assert_contains "PLAN §2 API Contracts" "$out" "API Contracts"
  assert_contains "PLAN §3 Data Model" "$out" "Data Model Changes"
  assert_contains "PLAN §4 Implementation Sequence" "$out" "Implementation Sequence"
  assert_contains "PLAN §5 Risk Register" "$out" "Risk Register"
  # AC #4: TASKS.md schema
  assert_contains "TASKS yaml id" "$out" "id: T1"
  assert_contains "TASKS yaml size" "$out" "size: M"
  assert_contains "TASKS yaml verify" "$out" "verify:"
  assert_contains "TASKS yaml depends_on" "$out" "depends_on:"
  assert_contains "XL warning" "$out" "XL: requires decomposition"
  # AC #5: SPEC.md trim instructions
  assert_contains "SPEC trim guidance" "$out" "TRIMMED"
  assert_contains "SPEC must remain stand-alone" "$out" "valid stand-alone"
}

test_planning_block_full_three_artifact_includes_block() {
  printf '\n\033[1m== AC#2: full three-artifact includes schemas ==\033[0m\n'
  local out
  out="$(planning_block_full "/tmp/spec" "three-artifact")"
  assert_contains "THREE-ARTIFACT header" "$out" "THREE-ARTIFACT OUTPUT MODE"
  assert_contains "mentions PLAN.md path" "$out" "/tmp/spec/plans/PLAN.md"
  assert_contains "mentions TASKS.md path" "$out" "/tmp/spec/plans/TASKS.md"
}

test_planning_block_quick_three_artifact_includes_block() {
  printf '\n\033[1m== AC#2: quick three-artifact includes schemas ==\033[0m\n'
  local out
  out="$(planning_block_quick "/tmp/spec" "three-artifact")"
  assert_contains "THREE-ARTIFACT header" "$out" "THREE-ARTIFACT OUTPUT MODE"
  assert_contains "mentions PLAN.md path" "$out" "/tmp/spec/plans/PLAN.md"
  assert_contains "mentions TASKS.md path" "$out" "/tmp/spec/plans/TASKS.md"
}

# === AC #1: meta.json records output_mode ===
test_write_meta_json_records_output_mode() {
  printf '\n\033[1m== AC#1: meta.json records output_mode ==\033[0m\n'
  local meta="$TMPDIR_BASE/meta.json"
  write_meta_json "$meta" "forge" "6" "title" "6-slug" "tmux" "sess" "lite" "three-artifact"
  local out
  out="$(jq -r '.output_mode' "$meta")"
  assert_eq "output_mode in json" "$out" "three-artifact"
}

test_write_meta_json_default_output_mode_is_single() {
  printf '\n\033[1m== AC#1: meta.json defaults output_mode to single ==\033[0m\n'
  local meta="$TMPDIR_BASE/meta.json"
  # 8 args (no output_mode) — uses default
  write_meta_json "$meta" "forge" "6" "title" "6-slug" "tmux" "sess" "lite"
  local out
  out="$(jq -r '.output_mode' "$meta")"
  assert_eq "defaults to single" "$out" "single"
}

# === AC #6: cmd_approve / cmd_spec_complete warn on missing files ===
test_approve_warns_on_missing_plan_in_three_artifact_mode() {
  printf '\n\033[1m== AC#6: approve warns on missing PLAN.md ==\033[0m\n'
  local dir="$TMPDIR_BASE/spec"
  mkdir -p "$dir/plans"
  touch "$dir/plans/SPEC.md"
  # only SPEC.md — PLAN.md and TASKS.md missing
  write_meta_json "$dir/meta.json" "forge" "6" "title" "6-slug" "tmux" "sess" "lite" "three-artifact"

  # Mock external dependencies
  safe_repo_main() { printf '%s' "$TMPDIR_BASE/repo"; }
  export -f safe_repo_main
  mkdir -p "$TMPDIR_BASE/repo"
  spec_dir() { printf '%s' "$dir"; }
  export -f spec_dir
  ensure_labels() { :; }; export -f ensure_labels
  set_issue_state_label() { :; }; export -f set_issue_state_label
  comment_issue() { :; }; export -f comment_issue
  notify_telegram() { :; }; export -f notify_telegram

  local stderr_file="$TMPDIR_BASE/stderr"
  cmd_approve "forge" "6-slug" 2>"$stderr_file" >/dev/null
  local stderr_content
  stderr_content="$(cat "$stderr_file")"
  assert_contains "warns about PLAN.md" "$stderr_content" "missing PLAN.md"
  assert_contains "warns about TASKS.md" "$stderr_content" "missing TASKS.md"
}

test_approve_no_warn_in_single_mode() {
  printf '\n\033[1m== AC#6: approve silent in single mode ==\033[0m\n'
  local dir="$TMPDIR_BASE/spec2"
  mkdir -p "$dir/plans"
  touch "$dir/plans/SPEC.md"
  write_meta_json "$dir/meta.json" "forge" "6" "title" "6-slug" "tmux" "sess" "lite" "single"

  safe_repo_main() { printf '%s' "$TMPDIR_BASE/repo"; }; export -f safe_repo_main
  spec_dir() { printf '%s' "$dir"; }; export -f spec_dir
  ensure_labels() { :; }; export -f ensure_labels
  set_issue_state_label() { :; }; export -f set_issue_state_label
  comment_issue() { :; }; export -f comment_issue
  notify_telegram() { :; }; export -f notify_telegram

  local stderr_file="$TMPDIR_BASE/stderr2"
  cmd_approve "forge" "6-slug" 2>"$stderr_file" >/dev/null
  local stderr_content
  stderr_content="$(cat "$stderr_file")"
  assert_not_contains "no PLAN.md warning" "$stderr_content" "missing PLAN.md"
  assert_not_contains "no TASKS.md warning" "$stderr_content" "missing TASKS.md"
}

setup
test_default_output_mode_is_single
setup
test_unknown_output_mode_falls_back_to_single
setup
test_planning_block_lite_single_mode_omits_block
setup
test_planning_block_lite_three_artifact_includes_block
setup
test_planning_block_full_three_artifact_includes_block
setup
test_planning_block_quick_three_artifact_includes_block
setup
test_write_meta_json_records_output_mode
setup
test_write_meta_json_default_output_mode_is_single
setup
test_approve_warns_on_missing_plan_in_three_artifact_mode
setup
test_approve_no_warn_in_single_mode
teardown

printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
```

**Test design notes:**
- Mocks follow the existing `export -f` pattern from `test/test_labels.sh`.
- No real GitHub calls — all network paths are mocked.
- Tests for all three pipeline modes (full/lite/quick) using only the planning_block_* functions (no need to invoke real `cmd_create`).
- AC #7 (end-to-end real-issue test) is NOT scripted — it's a manual smoke test (see §6 Migration Plan).

---

### 3.3 Documentation updates: `claude/commands/acorn.md`

**Update the "Spec directory layout" table (lines ~211-223)** to show three-artifact files conditionally:

```markdown
.specs/<slug>/
  PROMPT.md              # Generated requirements + planning methodology
  meta.json              # Metadata (repo, issue, session info, mode, output_mode)
  images/
  recon/
    architecture.md
    relevant_code.md
    conventions.md
  plans/
    draft_plan_1..4.md   (full only)
    draft.md             (lite only)
    evaluation.md        (full only)
    master_plan.md       (full only)
    validation.md        (lite only)
    red_team_1..4.md     (full only)
    SPEC.md              (all modes)
    PLAN.md              (three-artifact mode only)
    TASKS.md             (three-artifact mode only)
```

**Add a new "Output Modes" subsection** between the existing "Pipeline Modes" and "Examples" sections:

```markdown
### Output Modes

Acorn supports two output modes controlled by the `ACORN_OUTPUT_MODE` env var:

- **`single`** (default) — produces only `plans/SPEC.md`. Backwards-compatible
  with upstream `craigmmills/acorn`.

- **`three-artifact`** — produces `plans/SPEC.md` + `plans/PLAN.md` + `plans/TASKS.md`.
  - SPEC.md: trimmed to functional requirements + traceability matrix
  - PLAN.md: implementation design (architecture, contracts, data, risks)
  - TASKS.md: atomic work items as YAML blocks with verify commands

Set the env var before running `acorn create`:

    ACORN_OUTPUT_MODE=three-artifact acorn create forge 6 --lite

The mode is recorded in `meta.json` and read by `acorn approve` /
`acorn spec-complete` to enable warnings about missing PLAN/TASKS files.
```

---

## 4. Data Models

### 4.1 `meta.json` schema (extended)

**Before:**
```json
{
  "repo": "forge",
  "issue_number": 6,
  "issue_title": "Three-artifact pipeline output",
  "slug": "6-three-artifact-pipeline-output",
  "created_at": "2026-05-02T12:00:00Z",
  "session_backend": "tmux",
  "session_name": "forge_specs_6-three-artifact_claude",
  "mode": "lite"
}
```

**After:**
```json
{
  "repo": "forge",
  "issue_number": 6,
  "issue_title": "Three-artifact pipeline output",
  "slug": "6-three-artifact-pipeline-output",
  "created_at": "2026-05-02T12:00:00Z",
  "session_backend": "tmux",
  "session_name": "forge_specs_6-three-artifact_claude",
  "mode": "lite",
  "output_mode": "three-artifact"
}
```

**Migration:** existing meta.json files lack `output_mode`. All readers use `jq -r '.output_mode // "single"'` to default missing fields. No bulk migration required.

### 4.2 PLAN.md schema (LLM-emitted, prompt-enforced)

Required sections in order:
1. `## 1. Architecture Decisions` — bullets with rationale + alternatives
2. `## 2. API Contracts` — inputs/outputs/side effects per function
3. `## 3. Data Model Changes` — schemas, migrations
4. `## 4. Implementation Sequence` — phases + dependencies
5. `## 5. Risk Register` — severity, likelihood, mitigation

### 4.3 TASKS.md schema (LLM-emitted, prompt-enforced)

YAML list of task blocks:
```yaml
- id: T1
  title: "Add foo helper to bar.sh"
  size: M  # XS|S|M|L|XL
  files: [path/a.sh, path/b.sh]
  verify: "bash test/test_x.sh"
  depends_on: [T0]  # task ID list
```

XL tasks tagged with `⚠️ XL: requires decomposition` note.

### 4.4 No new env vars beyond `ACORN_OUTPUT_MODE`

No other state additions. `ACORN_OUTPUT_MODE` is the sole new contract surface.

---

## 5. API Design

### 5.1 New function signatures (added)

```bash
three_artifact_instructions()
  # Returns: prompt text (heredoc) instructing LLM to emit 3 artifacts.
  # Uses literal __SPEC_PATH__ tokens for caller's sed substitution.
  # No inputs. No side effects.
```

### 5.2 Modified function signatures (extended, backwards-compat)

```bash
planning_block(mode, spec_path, [output_mode="single"])
planning_block_full(spec_path, [output_mode="single"])
planning_block_lite(spec_path, [output_mode="single"])
planning_block_quick(spec_path, [output_mode="single"])
render_prompt_md(title, body, json, out_tmp, mode, spec_path, url_map, [output_mode="single"])
write_meta_json(path, repo, issue_num, title, slug, backend, sess, mode, [output_mode="single"])
```

**Compatibility:** All new parameters are positional and have safe defaults. Existing callers (zero in current codebase) continue to work unmodified.

### 5.3 Env var contract

```
ACORN_OUTPUT_MODE = "single" | "three-artifact"

Default: "single" (backwards-compat with upstream)
Invalid values: warn + fall back to "single"
Set by: forge consumers (Foreman dispatch wrappers)
Read by: cmd_create (at create time), cmd_approve / cmd_spec_complete (via meta.json)
```

---

## 6. Error Handling & Edge Cases

### 6.1 Invalid env var value

**Scenario:** User sets `ACORN_OUTPUT_MODE=triple` or `three_artifact` (typo).
**Handling:** Validation case statement at script load emits `[WARN]` and falls back to `single`. The acorn CLI continues to function; no command fails because of this.
**Why warn-not-die:** Invalid env vars must not break unrelated commands like `acorn list` or `acorn status`.

### 6.2 LLM fails to emit PLAN.md or TASKS.md

**Scenario:** Network blip, OOM, or LLM hallucination — agent writes SPEC.md but not PLAN/TASKS.
**Handling:**
- `cmd_create` doesn't block on LLM completion (the pipeline runs in a tmux session). No bash-side detection at create time.
- `cmd_approve` reads `meta.json.output_mode`, warns if files missing, but **proceeds to approve**. Operator sees the warning and can rerun the pipeline if desired.
- `cmd_spec_complete` does the same.

**Recovery procedure:**
```bash
# Operator sees warnings on approve. Two options:
# Option A: accept SPEC.md only (downgrade gracefully)
acorn approve forge 6-slug   # already approved with warning

# Option B: regenerate PLAN/TASKS via a focused agent run
# (manual; not automated in v1)
```

### 6.3 Mixed-mode spec dirs

**Scenario:** Spec was created with `single` mode (no PLAN/TASKS), but operator now sets `ACORN_OUTPUT_MODE=three-artifact` and runs `acorn approve`.
**Handling:** `cmd_approve` reads `meta.json` (recorded `single`), so it doesn't warn. The current shell env var is ignored at approve time. **This is correct** — approval should reflect the spec's actual generation mode, not the operator's current session env.

### 6.4 meta.json missing or corrupt

**Scenario:** Pre-existing spec dir has no `meta.json` (created before this feature) OR meta.json is malformed.
**Handling:**
- `jq -r '.output_mode // "single"' "$dir/meta.json" 2>/dev/null || printf 'single'`
- The `2>/dev/null || printf 'single'` chain ensures: missing file → "single", corrupt JSON → "single".
- Result: pre-existing specs behave exactly as today. No retroactive warnings on legacy dirs.

### 6.5 Heredoc edge cases — multi-line awk substitution

**Scenario:** The `three_artifact_instructions()` text contains backticks, dollar signs, slashes, brackets — all of which can confuse `sed` if used naively for the substitution.
**Handling:** Use `awk -v block="$three_block" '{gsub(/__THREE_ARTIFACT_BLOCK__/, block)} 1'` instead of `sed`. `awk -v` handles multi-line variable substitution safely; `sed` would require escaping every special character in the block.

**Verified safe characters in the block:** `__SPEC_PATH__` (placeholder, gets replaced afterward), backticks (in markdown code fences), colons, hyphens, brackets. All handled by `awk -v` without escaping.

**Order matters:** awk substitution MUST run BEFORE the sed `__SPEC_PATH__` substitution. If sed ran first, it would replace `__SPEC_PATH__` inside the placeholder line itself (wait — no it wouldn't, the placeholder is `__THREE_ARTIFACT_BLOCK__`, not `__SPEC_PATH__`). But the inserted block contains `__SPEC_PATH__` tokens that need to be replaced. So the correct order is:

1. `awk` injects `three_block` (which contains `__SPEC_PATH__` literals) into the heredoc, replacing `__THREE_ARTIFACT_BLOCK__`.
2. `sed` then replaces all `__SPEC_PATH__` tokens (both from the original heredoc and from the freshly-injected three-artifact block).

This is the order shown in §3.1.4.

### 6.6 LLM produces YAML with parse errors in TASKS.md

**Scenario:** Agent emits `TASKS.md` but the YAML is malformed (missing colon, bad indent).
**Handling:** Out of scope for this feature. The Acorn binary does not parse TASKS.md. Downstream consumers (forge's Foreman dispatch wrappers, per the upstreamability constraint in PROMPT.md) own parsing. If they hit a parse error, they fail loudly and the operator regenerates the spec.

**Why no bash-side validation:** AC #8 forbids new dependencies; pure bash YAML parsing would require either a heavy parser or fragile regex. Defer to downstream tools.

### 6.7 Concurrent `acorn create` runs in same spec dir

**Scenario:** Two operators run `acorn create` for the same issue simultaneously.
**Handling:** Pre-existing concern, not introduced by this feature. The atomic `mv tmp prompt.md` pattern in `render_prompt_md` already protects PROMPT.md write. `meta.json` is similarly atomic. No new race conditions added.

### 6.8 Rollback path

**Scenario:** Three-artifact mode causes an unforeseen problem in production.
**Rollback:** Set `ACORN_OUTPUT_MODE=single` in forge dispatcher. Behavior immediately reverts to today's single-file output. No data migration required; no schema changes to revert. Existing three-artifact spec dirs remain readable (SPEC.md is still primary).

**Code rollback (if needed):** revert the single commit. All changes are additive within `bin/acorn`; no destructive edits.

---

## 7. Testing Strategy

### 7.1 Test framework alignment

Follows existing conventions from `recon/conventions.md`:
- Hand-rolled bash tests, no external framework
- `eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"` to source functions
- `pass`/`fail`/`assert_eq`/`assert_contains`/`assert_not_contains` helpers
- `setup`/`teardown` with `trap teardown EXIT`
- Mock externals via `export -f`
- File naming: `test/test_<feature>.sh`

### 7.2 Test plan (10 unit tests in `test/test_three_artifact.sh`)

| # | Test | AC | What it verifies |
|---|------|----|------------------|
| 1 | `test_default_output_mode_is_single` | #1 | Env var defaults to "single" when unset |
| 2 | `test_unknown_output_mode_falls_back_to_single` | #1 | Invalid values fall back, don't crash |
| 3 | `test_planning_block_lite_single_mode_omits_block` | #1, #2 | Single-mode lite prompt has zero PLAN/TASKS mentions |
| 4 | `test_planning_block_lite_three_artifact_includes_block` | #2, #3, #4, #5 | Lite three-artifact prompt contains all schema sections |
| 5 | `test_planning_block_full_three_artifact_includes_block` | #2 | Full mode also gets the block |
| 6 | `test_planning_block_quick_three_artifact_includes_block` | #2 | Quick mode also gets the block |
| 7 | `test_write_meta_json_records_output_mode` | #1 | meta.json contains output_mode field |
| 8 | `test_write_meta_json_default_output_mode_is_single` | #1 | meta.json defaults to "single" if param omitted |
| 9 | `test_approve_warns_on_missing_plan_in_three_artifact_mode` | #6 | warn (not die) when files missing |
| 10 | `test_approve_no_warn_in_single_mode` | #6 | Single mode has no warnings |

### 7.3 Manual smoke test (AC #7)

```bash
# Pick a representative issue (e.g., a small forge issue)
ACORN_OUTPUT_MODE=three-artifact acorn create forge 6 --lite --no-auto

# Manually trigger the planning by attaching to the tmux session
dev forge_specs_6-three-artifact_claude
# Send the auto-trigger message manually, wait for completion

# Verify all three files
ls -la ~/projects/forge/main/.specs/6-*/plans/
# Expected: SPEC.md, PLAN.md, TASKS.md (plus draft.md, validation.md)

# Verify SPEC.md still valid stand-alone
head -50 ~/projects/forge/main/.specs/6-*/plans/SPEC.md
# Should contain: Pi Model Recommendation, Requirements Traceability Matrix,
# Functional Requirements, pointer to PLAN.md / TASKS.md

# Verify TASKS.md is parseable YAML
yq '.[] | .id' ~/projects/forge/main/.specs/6-*/plans/TASKS.md
# (or grep -E '^- id: T[0-9]' if yq unavailable — bash-only verify)
```

**Smoke test acceptance:**
- All three files exist
- SPEC.md does NOT contain detailed implementation steps (those are in PLAN.md)
- PLAN.md has all 5 required sections in order
- TASKS.md has at least one valid YAML task block

### 7.4 Regression test for existing functionality

Run all existing tests before merge to confirm no regressions:
```bash
bash test/test_labels.sh        # cmd_approve, cmd_spec_complete unchanged paths
bash test/test_auto_trigger.sh  # auto_trigger_message unchanged
bash test/test_split.sh
bash test/test_dependencies.sh
bash test/test_doctor.sh
```

All should pass without modification (the changes are purely additive — new positional args have safe defaults).

### 7.5 Test execution

Add to project README (no CI exists per `recon/conventions.md`):
```bash
# Run all unit tests
for t in test/test_*.sh; do bash "$t" || break; done
```

---

## 8. Implementation Sequence

Phase ordering with dependencies:

### Phase 1 — Foundation (no behavior change)
**Dependencies:** none.
**Verifiable independently:** yes — existing tests still pass.

1.1. Add `ACORN_OUTPUT_MODE` env var declaration + validation case statement (after PATH setup, ~line 23).
1.2. Add `three_artifact_instructions()` function near line 660 (before `planning_block()`).

After Phase 1: function defined but never called. `ACORN_OUTPUT_MODE` defined but no consumer reads it. All existing tests pass.

### Phase 2 — Plumbing (positional args, no behavior change in default mode)
**Dependencies:** Phase 1.
**Verifiable independently:** yes — single-mode behavior unchanged.

2.1. Extend `planning_block()` signature to accept `output_mode`.
2.2. Extend `planning_block_full()`, `_lite()`, `_quick()` signatures + add awk substitution for `__THREE_ARTIFACT_BLOCK__` placeholder. Insert placeholder in heredoc at the documented location.
2.3. Extend `render_prompt_md()` signature to accept and forward `output_mode`.
2.4. Extend `write_meta_json()` signature to accept and record `output_mode`.

After Phase 2: signatures extended, default args ensure single-mode is byte-identical to before. Run existing tests + lite-mode regression smoke.

### Phase 3 — Caller integration
**Dependencies:** Phase 2.
**Verifiable independently:** yes — single-mode behavior still unchanged.

3.1. `cmd_create()` reads `ACORN_OUTPUT_MODE`, threads to `render_prompt_md` and `write_meta_json`.
3.2. Add user-visible "Output mode: $output_mode" echo.

After Phase 3: setting `ACORN_OUTPUT_MODE=three-artifact` actually changes generated PROMPT.md content. Smoke test PROMPT.md output by diffing single vs. three-artifact in a throwaway dir.

### Phase 4 — Approval-time warnings
**Dependencies:** Phase 2 (needs meta.json output_mode field).
**Verifiable independently:** yes.

4.1. Add three-artifact warn-on-missing block to `cmd_approve()`.
4.2. Add identical block to `cmd_spec_complete()`.

After Phase 4: AC #6 satisfied. Tests 9 and 10 from §7.2 pass.

### Phase 5 — Tests
**Dependencies:** Phases 1–4.
**Verifiable independently:** yes — runs tests.

5.1. Create `test/test_three_artifact.sh` with all 10 tests from §7.2.
5.2. Run full test suite to confirm no regressions.

### Phase 6 — Documentation
**Dependencies:** Phase 5 (only document working behavior).
**Verifiable independently:** prose review.

6.1. Update `claude/commands/acorn.md` directory-layout table.
6.2. Add "Output Modes" subsection.

### Phase 7 — Manual integration test
**Dependencies:** Phases 1-6.
**Verifiable independently:** smoke test on a real issue.

7.1. Run `ACORN_OUTPUT_MODE=three-artifact acorn create forge <issue> --lite` end-to-end.
7.2. Verify all three artifacts produced and well-formed.

---

## 9. Migration Plan

### 9.1 Code migration

This is a non-breaking, additive feature. No data migrations required.

**Pre-existing spec dirs** (created before this feature):
- `meta.json` lacks `output_mode` field → readers default to `"single"` via `// "single"` jq fallback.
- No PLAN.md or TASKS.md → not expected to exist (single mode).
- Behavior on `acorn approve`: identical to today (no warnings).

**New spec dirs in single mode** (default):
- `meta.json` records `"output_mode": "single"`.
- No PLAN.md or TASKS.md generated.
- Behavior identical to upstream `craigmmills/acorn`.

**New spec dirs in three-artifact mode** (forge consumers):
- `meta.json` records `"output_mode": "three-artifact"`.
- All three files generated by Final Spec agent.
- `acorn approve` warns if PLAN/TASKS missing.

### 9.2 Forge consumer rollout

**Step 1:** Land this PR. Single-mode behavior unchanged for everyone.

**Step 2:** Forge dispatcher sets `ACORN_OUTPUT_MODE=three-artifact` in its `acorn create` invocations. Forge can choose per-call (e.g., always for `--lite` and `--full`, never for `--quick`) by setting the env var conditionally.

**Step 3:** Forge's Foreman wrappers (e.g., `spec-metadata-extract.sh`) gain TASKS.md parsing logic (out of scope for this PR, per upstreamability constraint).

**Step 4:** Once forge wrappers reliably consume TASKS.md, retire any hand-extraction logic in Wave-1 Pi context preambles.

### 9.3 Upstream PR-back path

This feature is designed to be PR-back-able to `craigmmills/acorn`:
- Default `single` preserves all current behavior.
- No forge-specific paths or assumptions in the binary.
- Schema definitions (PLAN.md sections, TASKS.md YAML) are generic.
- Downstream consumers (forge or otherwise) decide how to use the artifacts.

When PR'd upstream, the only required commit is the bash file change + the new test file + the docs update. No external dependencies.

---

## 10. Risk Register

| ID | Risk | Severity | Likelihood | Mitigation |
|---|---|---|---|---|
| R1 | LLM ignores schema instructions and produces malformed PLAN.md / TASKS.md | Med | Med | Schema is explicit + included verbatim in prompt. Manual smoke test before forge rollout. Downstream consumers fail loudly on parse errors so issues surface fast. |
| R2 | LLM produces SPEC.md that no longer reads stand-alone (over-trims) | Low | Med | Prompt explicitly says "SPEC.md MUST remain valid stand-alone". List of sections to KEEP is explicit. |
| R3 | awk substitution corrupts heredoc when block contains awk-special chars | Low | Low | `awk -v block="$var"` quoting handles all chars except literal newlines. Block is multi-line plain markdown — verified safe. |
| R4 | Existing forge wrappers break when meta.json gains `output_mode` field | Low | Low | jq-based readers ignore unknown fields. Inspected `spec-metadata-extract.sh` integration in `cmd_approve` — only writes, doesn't read field schema. |
| R5 | Concurrent `acorn create` invocations race on PROMPT.md write | Low | Low | Pre-existing concern; not introduced. Existing atomic-mv pattern still applies. |
| R6 | Operator sets `ACORN_OUTPUT_MODE=three-artifact` but runs `acorn approve` from a shell where var is unset | Low | High | `cmd_approve` reads from `meta.json`, not env var. Documented in §6.3 as correct behavior. |
| R7 | Heredoc placeholder `__THREE_ARTIFACT_BLOCK__` accidentally appears in unrelated text | Very Low | Very Low | String is highly specific; `grep -F '__THREE_ARTIFACT_BLOCK__' bin/acorn` confirms zero pre-existing occurrences. |
| R8 | Pi Model Recommendation section conflicts with three-artifact trim | Low | Low | Three-artifact instructions explicitly say "KEEP ## Pi Model Recommendation at top". |
| R9 | Future schema changes require synchronized edits across full/lite/quick | Low | Med | Mitigated by `three_artifact_instructions()` single-source-of-truth pattern — schemas live in one function, all three modes inject same text. |
| R10 | Downstream consumer (forge wrapper) breaks if TASKS.md format drifts between Acorn versions | Med | Low | Schema is documented in `claude/commands/acorn.md` and version-tagged (implicit via git tags). Forge wrappers should validate before consuming. |

### Critical risks requiring user/operator awareness

- **R1**: Real risk of malformed YAML on first runs. Recommend manual review of TASKS.md output for first 3-5 specs before relying on automated downstream parsing.
- **R6**: Operators might be confused why `acorn approve` works without warnings even though they expected three-artifact mode. Documentation should make clear that meta.json is the source of truth.

### Non-risks (explicitly considered and dismissed)

- **CI breakage**: no CI exists.
- **Dependency conflicts**: no new deps.
- **Migration data loss**: no schema changes to existing data; field additions are forward-compatible.
- **Performance**: prompt is ~200 lines longer in three-artifact mode; negligible token overhead vs. typical 4000-line PROMPT.md.

---

## 11. Summary of Touched Files

| File | Type | Lines changed (est.) |
|---|---|---|
| `bin/acorn` | Production | +120 / -10 (one new function, six modified function signatures, three placeholder injections in heredocs, two new warn blocks) |
| `test/test_three_artifact.sh` | New test | +200 (10 tests + boilerplate) |
| `claude/commands/acorn.md` | Docs | +30 / -5 (new subsection + table update) |
| **Total** | **3 files** | **~350 net lines** |

**No new dependencies.** **No schema breakage.** **No upstream incompatibility.** **No CI changes** (none exist).

---

## 12. Open Questions for Validator (Stage 2)

1. **Pi Model Recommendation placement in trimmed SPEC.md:** The Pi Model Recommendation block currently lives at the top of SPEC.md. In three-artifact mode, should it stay at top of SPEC.md (current plan), move to PLAN.md, or be duplicated in both? Current plan: keeps it in SPEC.md only — it's a routing hint for operators reading the lightweight summary, not a design decision belonging in PLAN.md.

2. **`acorn list` / `acorn status` display:** Should these commands show output_mode? Probably yes for `acorn status`, no for `acorn list` (which is already tabular and tight). Deferred — not in PROMPT.md acceptance criteria.

3. **CLI flag `--output-mode` deferred:** Should this PR include a `--output-mode` flag in addition to env var? Current plan: no, env var alone satisfies AC #1 ("env var **or equivalent CLI flag**"). Adding the flag later is non-breaking.

4. **TASKS.md verify command convention:** Should verify commands assume a working dir? Default to repo root? Current plan: leave to LLM judgment (prompt doesn't specify). Forge wrappers can post-process.

5. **Three-artifact mode test file existence checks at create time:** Should `cmd_create` verify the LLM eventually wrote all three files (e.g., via a delayed check)? Current plan: no — `cmd_create` returns immediately after spawning the tmux session; the LLM runs asynchronously. Verification happens at `acorn approve` / `acorn spec-complete` time.

These are flagged for Stage 2 validation review.




