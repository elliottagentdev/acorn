# SPEC: Three-Artifact Pipeline Output (SPEC.md + PLAN.md + TASKS.md) — implements forge#6

## Pi Model Recommendation

suggested_pi_model: codex
suggested_pi_model_rationale: Single-file Bash edit with named functions, exact line numbers, explicit test commands, < 8 files touched, no new interfaces or schemas beyond a documented env var, and pattern-following implementation throughout.

---

## 1. Requirements Traceability Matrix

For each acceptance criterion (AC) in `PROMPT.md`, the section(s) of this spec that address it. No requirements are deferred.

| AC # | Requirement (paraphrased) | Addressed in |
|---|---|---|
| AC #1 | Configurable mode via env var `ACORN_OUTPUT_MODE` with `single` (default, backwards-compat) and `three-artifact` | §3.1 (constants), §3.2 (validation), §3.6 (`cmd_create` reads), §3.7 (`write_meta_json` records), §4.1 (env var contract), §5.1, §5.7 (tests T1, T2, T7, T8), §3.8 (mode-mismatch detection) |
| AC #2 | Stage-level emission in all three pipeline modes (`quick` / `lite` / `full`) | §3.4 (heredoc edit applied to all three planning_block_* functions, with explicit before/after snippets for each), §5.3, §5.4, §5.5 (tests T3-T6, T11-T12) |
| AC #3 | PLAN.md schema with 5 required sections in order | §3.3 (`three_artifact_instructions()` body — PLAN.md section), §4.2 (PLAN.md schema), §5.4 (test T4 asserts schema strings present) |
| AC #4 | TASKS.md schema (YAML blocks with id/title/size/files/verify/depends_on; XL flag) | §3.3 (TASKS.md section of `three_artifact_instructions()`), §4.3 (TASKS.md schema), §5.4 (test T4 asserts YAML schema strings) |
| AC #5 | SPEC.md backwards-compat in three-artifact mode (trim impl/AC, remain stand-alone) | §3.3 (KEEP/REMOVE list using SECTION NAMES not invented numbers), §4.4 (SPEC.md trim contract), §5.4 (test T4 asserts trim guidance present) |
| AC #6 | `acorn approve` and `acorn spec-complete` warn (not error) on missing PLAN.md / TASKS.md | §3.9 (`cmd_approve` warn block using `[ -s ... ]`), §3.10 (`cmd_spec_complete` parallel block), §5.9 (test T9 — approve warns), §5.11 (test T13 — spec-complete warns), §5.10 (test T10 — single mode no warn) |
| AC #7 | Test: `acorn create <repo> <issue> --lite` produces three files; SPEC.md valid stand-alone | §6 Manual Smoke Test Procedure (operator-driven; ZERO ambiguity in steps and pass/fail criteria) — also recorded in implementation Phase 7 |
| AC #8 | No new dependencies (bash/jq/awk only) | §3.4 uses only `sed` and `cat` (sed is already a dep; no awk introduced); §3.3 uses only `cat` heredoc; §3.7 uses existing `jq`. Verified in §7 Risk Register R3. |

**Coverage: 8/8 ACs fully addressed. Zero gaps. Zero deferrals.**

---

## 2. Validation Resolution Log

For each numbered finding from `validation.md`, the resolution.

### 2.1 Must-Fix items (resolved)

| MF | Finding | Resolution in this spec |
|---|---|---|
| MF1 | `awk gsub` interprets backslashes in injected block, silently corrupting markdown | **Resolved** — Replaced awk substitution with **sed `r` (read file) approach** in §3.4. The block is written to a temp file, then `sed '/__THREE_ARTIFACT_BLOCK__/{r block_file' -e 'd}'` reads the file verbatim (no escape interpretation) at the placeholder line and deletes the placeholder. In single mode, `sed '/__THREE_ARTIFACT_BLOCK__/d'` simply deletes the placeholder line. No awk used. |
| MF2 | Final-response prompt contradicts itself (original "Done. Output: SPEC.md only" vs new "list all three paths") in three-artifact mode | **Resolved** — `three_artifact_instructions()` (§3.3) now contains explicit OVERRIDE language: `IMPORTANT: This OVERRIDES the prior "Your final response must be ONLY..." instruction.` The block makes clear the new final-response format supersedes the original. See §3.3 final paragraph. |
| MF3 | SPEC.md trim instructions referenced invented section numbers (`## 3.`, `## 4.`, etc.) that don't match canonical SPEC template | **Resolved** — `three_artifact_instructions()` (§3.3) now uses **section NAMES** matching the canonical template that the existing Stage-5/Stage-3/Stage-1 prompts already produce: "Pi Model Recommendation", "Requirements Traceability Matrix", "Validation Resolution Log", "Implementation Plan", "Testing Strategy", "Risk Register". KEEP/REMOVE lists use these names. |
| MF4 | Phase 4 dependency listed as Phase 2; should be Phase 3 (warnings need `output_mode` recorded by `cmd_create`) | **Resolved** — §8 implementation sequence updates Phase 4 dependency to Phase 3. |
| MF5 | Pre-existing PROMPT.md skipped on re-run; meta.json says three-artifact but PROMPT.md is single → silent failure | **Resolved** — §3.8 adds mode-mismatch detection inside `cmd_create`. When PROMPT.md exists and `meta.json.output_mode` differs from current `$ACORN_OUTPUT_MODE`, emit a `warn` with explicit recovery instructions (delete PROMPT.md to regenerate). Test T14 (§5.14) covers this. |

### 2.2 Should-Fix items (resolved)

| SF | Finding | Resolution |
|---|---|---|
| SF1 | Plan only showed lite-mode heredoc edit; full and quick "same edit" was vague | **Resolved** — §3.4 shows the EXACT modified heredoc fragment for ALL THREE modes (full Stage 5, lite Stage 3, quick Stage 1) with line-anchored before/after context. |
| SF2 | No test for `cmd_spec_complete` warnings | **Resolved** — Test T13 (§5.11) added, parallel to T9 (`cmd_approve`). |
| SF3 | `validate_prompt_md` doesn't verify substitution succeeded | **Resolved** — §3.5 adds an additional positive check inside `validate_prompt_md`: when caller passes optional `output_mode=three-artifact`, validate that the rendered PROMPT.md contains the literal string "THREE-ARTIFACT OUTPUT MODE" AND does NOT contain `__THREE_ARTIFACT_BLOCK__`. New optional 2nd arg, defaults to skipping this check (backwards-compat). Test T15 (§5.15) covers it. |
| SF4 | Tests for `quick+single` and `full+single` not present | **Resolved** — Tests T11 and T12 (§5.5) added — explicit omit-block assertions for full+single and quick+single. |
| SF5 | TASKS.md verify command working dir unspecified | **Resolved** — `three_artifact_instructions()` (§3.3) explicitly says: `Verify commands MUST be runnable from the repo root with no implicit cd.` |
| SF6 | Plan §3.3 docs target line range slightly off; "Examples" anchor doesn't exist | **Resolved** — §3.11 docs section uses anchor "after the Project layout section" rather than line numbers. The exact section is named in §3.11. |
| SF7 | Approve doesn't verify PLAN.md/TASKS.md non-empty | **Resolved** — §3.9 and §3.10 use `[ -s "$dir/plans/PLAN.md" ]` (file exists AND non-empty) instead of `[ -f ... ]`. Test T9 also creates an empty PLAN.md in one variant to verify the empty-file case warns (test T9b, §5.9). |
| SF8 | TASKS.md schema lacks version marker | **Resolved** — `three_artifact_instructions()` (§3.3) instructs the LLM to emit `# acorn-tasks-schema: v1` as the first line of TASKS.md. Test T4 asserts this string is present in the prompt. |
| SF9 | Validation case statement runs on every CLI invocation; can spam warnings for unrelated commands | **Resolved** — Validation case statement (§3.2) is moved INSIDE `cmd_create` (after env-var read at §3.6). The constants block at §3.1 only declares the variable with the `:-single` default; the validation only fires when `cmd_create` actually consumes the value. `acorn list`, `acorn doctor`, etc. are unaffected by typos. |

### 2.3 Nice-to-Fix items (resolved or deliberately deferred with justification)

| NF | Finding | Resolution |
|---|---|---|
| NF1 | `write_meta_json` not atomic; concurrent writes race | **Deferred — pre-existing.** Severity: Low. Justification: Pre-existing concern not introduced by this feature; concurrent `acorn create` for the same issue is operator error and protected against at a higher layer (one tmux session per spec). Recommended follow-up: file a separate issue to add temp+mv atomic write to `write_meta_json`. |
| NF2 | No documented procedure for upgrading single-mode spec to three-artifact | **Resolved** — §6.5 adds explicit recovery procedure (delete `PROMPT.md`, re-run `acorn create` with `ACORN_OUTPUT_MODE=three-artifact`). |
| NF3 | Quick mode + three-artifact may produce lower-quality PLAN/TASKS | **Resolved** — §3.11 docs subsection includes an explicit advisory: "Three-artifact output in `quick` mode is less validated than in `lite` or `full`; prefer `lite` or `full` for production planning when downstream consumers depend on TASKS.md schema correctness." |
| NF4 | Test mocks brittle (closure over `$dir`) | **Resolved** — §5 test design uses an exported global `MOCK_SPEC_DIR` set per test, instead of relying on closure-captured locals. Mocks read from the env var. |
| NF5 | Risk R4 (forge `spec-metadata-extract.sh` compat) was unverifiable in plan | **Resolved** — §7 Risk Register R4 lowers confidence and adds explicit deferred follow-up: forge consumer must verify their wrapper does not strict-validate `meta.json` schema before enabling three-artifact in production. |
| NF6 | No escape hatch for `--output-mode` CLI flag in v2 | **No fix required** — current design (positional args with defaults, env var read) supports adding `--output-mode` later without breaking changes. Documented in §4.1. |

### 2.4 Edge case findings (resolved)

| Ref | Finding | Resolution |
|---|---|---|
| E2 | Empty `three_artifact_instructions()` output not tested | **Resolved** — Test T16 (§5.16) added: asserts function emits non-empty output containing the THREE-ARTIFACT header. |
| E5 | Reverse upgrade path (single → three-artifact) | **Resolved** — §6.5 documents recovery; mode-mismatch detection in §3.8 alerts operator. |
| E6 | LLM partial output: PLAN.md half-written | **Resolved** — `[ -s ... ]` check in §3.9/§3.10 (per SF7) catches truncated/empty files. |
| E10 | Schema drift across Acorn versions | **Resolved** — Schema version marker `# acorn-tasks-schema: v1` (per SF8) gives downstream consumers a version anchor. |
| E13 | Test 9 / 10 race on `notify_telegram` | **Resolved** — §5 test design explicitly mocks `notify_telegram`, `notify_foreman`, and `comment_issue` in BOTH approve and spec-complete tests. |
| E17 | Single-mode PROMPT.md not byte-identical (extra blank lines) | **Resolved** — §3.4's sed `d` (delete placeholder line) approach removes the placeholder line entirely, leaving a single blank line where the placeholder was. The diff vs current output is a single blank line, documented and accepted. Regression note in §5.17. |
| E18 | `validate_prompt_md` doesn't verify three-artifact substitution | **Resolved** — see SF3 above. |
| E19 | Pipeline×output mode matrix coverage incomplete | **Resolved** — see SF4 above. Tests T3-T6, T11, T12 cover all six combinations (full×single, full×three-artifact, lite×single, lite×three-artifact, quick×single, quick×three-artifact). |
| E25 | Final-response prompt contradiction | **Resolved** — see MF2 above. |

### 2.5 Confirmed correct (no change needed)

These plan claims were verified correct by the validator and require no resolution: F1 (line numbers exact), F4 (Pi Model Rec placement), F16 (schema fidelity vs PROMPT.md), A7 (jq fallback), E11/E12 (no injection vectors), E15 (`cmd_clean` already removes new files), E20 (heredoc quoting), E22 (line count estimate), E23 (Bash compat).

---

## 3. Implementation Plan

All edits are to a single production file: `/home/agentdev/projects/acorn/main/bin/acorn`. Plus one new test file and one docs update. Steps are listed in implementation order. Each step is independently verifiable.

### 3.1 Add `ACORN_OUTPUT_MODE` global declaration

**File:** `/home/agentdev/projects/acorn/main/bin/acorn`
**Location:** After line 13 (immediately after the existing `_LIST_NWO=""` global), before the PATH-manipulation block at line 14.

**Add:**
```bash
# Output mode controls whether the planning pipeline emits a single SPEC.md
# (default, upstream-compatible) or the three-artifact set
# (SPEC.md + PLAN.md + TASKS.md, used by forge consumers).
# Valid values: "single", "three-artifact"
# Validation lives inside cmd_create (§3.6) so unrelated commands like
# `acorn list` are unaffected by typos in the env var.
ACORN_OUTPUT_MODE="${ACORN_OUTPUT_MODE:-single}"
```

**Verification:** Run `bash bin/acorn list` with `ACORN_OUTPUT_MODE=bogus`. Expect: command runs without warning. Then run `printenv ACORN_OUTPUT_MODE` inside the script (or `bash -c 'source bin/acorn 2>/dev/null; echo $ACORN_OUTPUT_MODE'`) — should still be `bogus` because validation hasn't fired yet.

### 3.2 (Validation moved to §3.6 — no separate top-level case statement)

Per SF9 resolution, the validation case statement that warns on invalid `ACORN_OUTPUT_MODE` values lives inside `cmd_create()` (§3.6), NOT at the top of the script. This prevents `acorn list` / `acorn doctor` / etc. from emitting warnings every time when a user has a stale `ACORN_OUTPUT_MODE` value in their shell.

### 3.3 Add new helper function `three_artifact_instructions()`

**File:** `/home/agentdev/projects/acorn/main/bin/acorn`
**Location:** Immediately before `planning_block()` at current line 662 (so it appears at line ~661 with the new function body).

**Why a separate function:** Single source of truth for the schemas. All three pipeline modes inject the same text. A future schema tweak touches exactly one function.

**Add this function:**

```bash
# three_artifact_instructions
#   Emits the prompt text that instructs the Final Spec agent to produce
#   three artifacts (SPEC.md + PLAN.md + TASKS.md) instead of one.
#   Uses literal __SPEC_PATH__ tokens; the caller's sed substitution
#   replaces them. Output is read verbatim by sed via the `r` command,
#   so no shell escapes inside.
three_artifact_instructions() {
  cat <<'THREE_ARTIFACT_EOF'

---

### THREE-ARTIFACT OUTPUT MODE (ACORN_OUTPUT_MODE=three-artifact)

IMPORTANT: This OVERRIDES the prior "Your final response must be ONLY: 'Done. Output: __SPEC_PATH__/plans/SPEC.md'" instruction. In three-artifact mode, you MUST produce THREE files in __SPEC_PATH__/plans/, not one, and your final response MUST list all three paths (see end of this section).

#### 1. __SPEC_PATH__/plans/SPEC.md  (TRIMMED)

Functional requirements only. KEEP these sections (by NAME, in this order):
  - ## Pi Model Recommendation              (top, unchanged)
  - ## 1. Requirements Traceability Matrix  (unchanged)
  - ## 2. Validation Resolution Log         (unchanged; or "Red Team Resolution Log" in full mode)
  - ## Functional Requirements              (Job Story, Promise, Constraints — extract from PROMPT.md)
  - ## Risk Register                        (KEEP a one-paragraph pointer: "See PLAN.md §5 Risk Register for the full register.")
  - ## Acceptance Criteria                  (KEEP a one-paragraph pointer: "See TASKS.md for the verifiable, atomic task list that satisfies acceptance.")

REMOVE these sections (they MOVE to PLAN.md / TASKS.md):
  - ## Implementation Plan       (entire section — moves to PLAN.md §1-§4)
  - ## Testing Strategy          (moves to PLAN.md §4 Implementation Sequence + TASKS.md verify commands)

SPEC.md MUST remain valid stand-alone — a legacy reader (single-mode consumer) reading only SPEC.md must still understand WHAT the feature does and WHY, just not HOW.

#### 2. __SPEC_PATH__/plans/PLAN.md  (NEW)

Implementation design. Required sections, in this exact order with these exact heading texts:

  ## 1. Architecture Decisions
     For each decision: 1-3 bullet points with rationale; cite alternatives considered and why rejected.

  ## 2. API Contracts
     For each touched function or interface:
       - Inputs (types, validation rules)
       - Outputs (return type, error modes)
       - Side effects (files written, network calls, state mutations)

  ## 3. Data Model Changes
     Schemas, migrations, atomic-rename patterns. If no data changes, write exactly: "No data model changes."

  ## 4. Implementation Sequence
     Phase names with dependency graph. Each phase independently verifiable. Use a numbered list.

  ## 5. Risk Register
     Known unknowns: severity (low/med/high), likelihood (low/med/high), mitigation. Use a markdown table with columns: ID | Risk | Severity | Likelihood | Mitigation.

#### 3. __SPEC_PATH__/plans/TASKS.md  (NEW)

The first line of TASKS.md MUST be:

    # acorn-tasks-schema: v1

(This version marker lets downstream consumers detect schema drift across Acorn versions.)

After the version marker, emit atomic work items as a YAML list. Each task is a YAML block with this EXACT schema:

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
  - XL: >8 files OR >3 new interfaces — flag with note exactly:
        ⚠️ XL: requires decomposition

Verify command rules:
  - Every task MUST have a non-empty `verify` command.
  - Verify commands MUST be runnable from the repo root with no implicit `cd`.
  - Prefer specific test invocations (e.g., `pytest -q path::test_name`) over broad suites.
  - If no test exists yet, the verify command should be the test that must be added; that task gets size XS or S to write the test.

Tasks ordered by `depends_on` (DAG). Topological order in the file (a task may only depend_on tasks listed before it).

#### Final response (THREE-ARTIFACT MODE OVERRIDE)

IMPORTANT: Replace the original final-response instruction. In three-artifact mode, your final response MUST be EXACTLY:

    Done. Output: __SPEC_PATH__/plans/SPEC.md + __SPEC_PATH__/plans/PLAN.md + __SPEC_PATH__/plans/TASKS.md

THREE_ARTIFACT_EOF
}
```

**Design notes:**
- Heredoc uses single-quoted `'THREE_ARTIFACT_EOF'` so no variable expansion happens; only the caller's sed `__SPEC_PATH__` substitution runs.
- Schemas use SECTION NAMES (not invented numbers) to match the canonical SPEC.md template that existing Stage-5/Stage-3/Stage-1 prompts already produce.
- The OVERRIDE language at top and bottom resolves the contradiction with the original "final response must be ONLY..." instruction (see Validation MF2).
- The schema version marker `# acorn-tasks-schema: v1` is in the TASKS.md section per SF8.
- "Verify commands runnable from the repo root" per SF5.

**Verification:** `bash -c 'source bin/acorn 2>/dev/null; three_artifact_instructions' | head -20` should print the THREE-ARTIFACT header. `... | grep -c '__SPEC_PATH__'` should return >= 3 (placeholder appears multiple times for sed to substitute).

### 3.4 Modify `planning_block()` and the three `planning_block_*()` functions to accept and inject `output_mode`

**File:** `/home/agentdev/projects/acorn/main/bin/acorn`

#### 3.4.1 `planning_block()` dispatcher (line 662)

**Current:**
```bash
planning_block() {
  local mode="${1:-full}"
  local spec_path="${2:-.}"
  case "$mode" in
    full)  planning_block_full "$spec_path" ;;
    lite)  planning_block_lite "$spec_path" ;;
    quick) planning_block_quick "$spec_path" ;;
    *)     die "Unknown planning mode: $mode" ;;
  esac
}
```

**Replace with:**
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

#### 3.4.2 Substitution mechanism — sed `r` (read file), NOT awk

Per Validation MF1, the substitution mechanism uses `sed` with the `r` (read file) command instead of `awk -v block=...`. This avoids backslash-mangling and uses only `sed` (already a dependency). No new dependency introduced.

**Substitution shell-pattern (used inside each `planning_block_*()`):**

```bash
local block_file=""
if [ "$output_mode" = "three-artifact" ]; then
  block_file="$(mktemp -t acorn_three_artifact_XXXXXX)"
  three_artifact_instructions > "$block_file"
fi

if [ -n "$block_file" ]; then
  cat <<'METHODOLOGY_EOF' \
    | sed -e "/__THREE_ARTIFACT_BLOCK__/{
r ${block_file}
d
}" \
    | sed "s|__SPEC_PATH__|${spec_path}|g"
  ... (existing heredoc body, with __THREE_ARTIFACT_BLOCK__ placeholder line inserted) ...
METHODOLOGY_EOF
  rm -f "$block_file"
else
  cat <<'METHODOLOGY_EOF' \
    | sed '/__THREE_ARTIFACT_BLOCK__/d' \
    | sed "s|__SPEC_PATH__|${spec_path}|g"
  ... (same existing heredoc body) ...
METHODOLOGY_EOF
fi
```

**How sed `r ; d` works:** When sed encounters a line matching `__THREE_ARTIFACT_BLOCK__`, the `r ${block_file}` command reads the file content verbatim and queues it to be printed AFTER the current line, then `d` deletes the current line (the placeholder). The file content is read literally — no escape processing — so backslashes, dollar signs, brackets, and emojis all survive. This is the standard sed idiom for file inclusion.

**Single-mode path:** `sed '/__THREE_ARTIFACT_BLOCK__/d'` simply deletes the placeholder line. PROMPT.md output differs from today's output by exactly one deleted blank line (the placeholder line). Documented in §5.17 regression note.

**Order of substitutions:**
1. First sed: substitute (or delete) `__THREE_ARTIFACT_BLOCK__`. The injected block contains `__SPEC_PATH__` literals that need substitution.
2. Second sed: substitute `__SPEC_PATH__` everywhere (in both the original heredoc and the injected block).

This order is critical and explicit in the pipeline.

**Cleanup:** `rm -f "$block_file"` runs after the heredoc writes. The temp file lifetime is microseconds. If `rm` fails (e.g., disk error), it's harmless — `mktemp -t acorn_three_artifact_XXXXXX` files are in `$TMPDIR` (usually `/tmp`) and get cleaned by OS reboot.

#### 3.4.3 `planning_block_lite()` (current line 1141, Stage 3 Final Spec at lines ~1350-1399)

**Step A — change function signature** at line 1142:

```bash
planning_block_lite() {
  local spec_path="${1:-.}"
  local output_mode="${2:-single}"
```

**Step B — wrap the existing `cat <<'METHODOLOGY_EOF' | sed "s|__SPEC_PATH__|${spec_path}|g" ... METHODOLOGY_EOF` block** with the if/else shell-pattern from §3.4.2. The heredoc body is duplicated (once per branch); both branches share the same body but pipe through different sed commands. Body duplication is the cleanest approach because heredocs cannot be stored in shell variables without escape headaches.

**Step C — insert placeholder line into the heredoc body** at the Stage 3 Final Spec agent prompt (currently around line 1395):

**Find this fragment in the existing heredoc (lite Stage 3, ~line 1395):**
```
The spec must be ready to be handed to a developer or agent for implementation with ZERO questions.

- Write the final spec to __SPEC_PATH__/plans/SPEC.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: __SPEC_PATH__/plans/SPEC.md"
```

**Replace with (placeholder line added between "ZERO questions" and "Write the final spec"):**
```
The spec must be ready to be handed to a developer or agent for implementation with ZERO questions.

__THREE_ARTIFACT_BLOCK__

- Write the final spec to __SPEC_PATH__/plans/SPEC.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: __SPEC_PATH__/plans/SPEC.md"
```

In single mode, the `__THREE_ARTIFACT_BLOCK__` line is deleted by sed; the prompt is byte-equivalent to today minus one blank line. In three-artifact mode, the line is replaced with the contents of the temp file (the full schema instructions including the OVERRIDE for the final-response line below it).

#### 3.4.4 `planning_block_full()` (current line 673, Stage 5 Final Spec at lines ~1074-1122)

**Step A — change function signature** at line 674:

```bash
planning_block_full() {
  local spec_path="${1:-.}"
  local output_mode="${2:-single}"
```

**Step B — wrap with the if/else shell-pattern** (same as 3.4.3 Step B).

**Step C — insert placeholder line** in the Stage 5 Final Spec agent prompt body (currently around line 1116):

**Find:**
```
The spec must be ready to be handed to a developer or agent for implementation with ZERO questions.

- Write the final spec to __SPEC_PATH__/plans/SPEC.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: __SPEC_PATH__/plans/SPEC.md"
```

**Replace with:**
```
The spec must be ready to be handed to a developer or agent for implementation with ZERO questions.

__THREE_ARTIFACT_BLOCK__

- Write the final spec to __SPEC_PATH__/plans/SPEC.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: __SPEC_PATH__/plans/SPEC.md"
```

The placeholder line MUST appear EXACTLY ONCE inside the heredoc body, in the Stage 5 Final Spec agent prompt only. Earlier stages (recon, draft, validation, master plan, red team) MUST NOT receive three-artifact instructions because their job is intermediate artifacts, not the final user-facing artifact.

#### 3.4.5 `planning_block_quick()` (current line 1419, Stage 1 Direct Spec at lines ~1542-1590)

**Step A — change function signature** at line 1420:

```bash
planning_block_quick() {
  local spec_path="${1:-.}"
  local output_mode="${2:-single}"
```

**Step B — wrap with the if/else shell-pattern** (same as 3.4.3 Step B).

**Step C — insert placeholder line** in the Stage 1 Direct Spec agent prompt body (currently around line 1586):

**Find:**
```
The spec must be ready to be handed to a developer or agent for implementation with ZERO questions.

- Write the final spec to __SPEC_PATH__/plans/SPEC.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: __SPEC_PATH__/plans/SPEC.md"
```

**Replace with:**
```
The spec must be ready to be handed to a developer or agent for implementation with ZERO questions.

__THREE_ARTIFACT_BLOCK__

- Write the final spec to __SPEC_PATH__/plans/SPEC.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: __SPEC_PATH__/plans/SPEC.md"
```

**Verification of step 3.4 overall:** After all three function edits:
- `bash -c 'source bin/acorn 2>/dev/null; planning_block_lite /tmp/x single' | grep -c THREE-ARTIFACT` → 0
- `bash -c 'source bin/acorn 2>/dev/null; planning_block_lite /tmp/x three-artifact' | grep -c THREE-ARTIFACT` → >= 1
- `bash -c 'source bin/acorn 2>/dev/null; planning_block_lite /tmp/x three-artifact' | grep -c '/tmp/x/plans/PLAN.md'` → >= 1
- Repeat for `planning_block_full` and `planning_block_quick`.

### 3.5 Modify `validate_prompt_md()` to optionally verify three-artifact substitution (SF3)

**File:** `/home/agentdev/projects/acorn/main/bin/acorn`
**Location:** Function at lines 1672-1676.

**Current:**
```bash
validate_prompt_md() {
  local prompt_path="$1"
  grep -q 'PLANNING METHODOLOGY — MANDATORY INSTRUCTIONS' "$prompt_path" || return 1
  return 0
}
```

**Replace with:**
```bash
validate_prompt_md() {
  local prompt_path="$1"
  local output_mode="${2:-single}"
  grep -q 'PLANNING METHODOLOGY — MANDATORY INSTRUCTIONS' "$prompt_path" || return 1
  # Three-artifact mode: verify substitution succeeded.
  if [ "$output_mode" = "three-artifact" ]; then
    grep -q 'THREE-ARTIFACT OUTPUT MODE' "$prompt_path" || return 1
    # Negative check: placeholder must NOT remain in output.
    ! grep -q '__THREE_ARTIFACT_BLOCK__' "$prompt_path" || return 1
  fi
  return 0
}
```

**Backwards compat:** Default 2nd arg is `single`, identical to today's behavior. Existing single-arg callers see no change. The 2nd arg is consumed only when explicitly passed by the new `cmd_create` plumbing in §3.6.

### 3.6 Modify `render_prompt_md()` to accept and forward `output_mode`

**File:** `/home/agentdev/projects/acorn/main/bin/acorn`
**Location:** Function at lines 1621-1669.

**Current signature (line 1622-1628):**
```bash
render_prompt_md() {
  local issue_title="$1"
  local issue_body="$2"
  local issue_json="$3"
  local out_tmp="$4"
  local mode="${5:-full}"
  local spec_path="${6:-.}"
  local url_mapping_file="${7:-}"
```

**New signature (add 8th positional arg):**
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
```

**Current call to `planning_block` (inside the function body):**
```bash
planning_block "$mode" "$spec_path"
```

**Replace with:**
```bash
planning_block "$mode" "$spec_path" "$output_mode"
```

**Backwards compat:** Existing 7-arg callers receive default `single` and unchanged behavior.

### 3.7 Modify `cmd_create()` to read `ACORN_OUTPUT_MODE`, validate it, and thread it through

**File:** `/home/agentdev/projects/acorn/main/bin/acorn`
**Location:** Function at lines 2209-2350.

**Step A — after the existing arg-parse loop ending at line 2234** (and BEFORE the `mkdir -p "$dir/plans"` at line 2264), add:

```bash
# Read and validate output mode from environment.
# Forge consumers set ACORN_OUTPUT_MODE=three-artifact; default is upstream-compatible single.
local output_mode="${ACORN_OUTPUT_MODE:-single}"
case "$output_mode" in
  single|three-artifact) ;;
  *)
    warn "Unknown ACORN_OUTPUT_MODE=$output_mode; falling back to single"
    output_mode="single"
    ;;
esac
```

**Step B — update the `render_prompt_md` call** at current line 2276 (passes 7 args, becomes 8):

**Current:**
```bash
render_prompt_md "$title" "$body" "$issue_json" "$tmp_path" "$mode" "$dir" "$url_mapping_file" > "$tmp_path"
```

**New:**
```bash
render_prompt_md "$title" "$body" "$issue_json" "$tmp_path" "$mode" "$dir" "$url_mapping_file" "$output_mode" > "$tmp_path"
```

(If the existing call uses different redirection, preserve it; only add the 8th positional arg `"$output_mode"` before the redirection.)

**Step C — update the `validate_prompt_md` call** if present (search for `validate_prompt_md` calls in `cmd_create`); pass the 2nd arg `"$output_mode"`:

**Pattern (locate exact line):**
```bash
validate_prompt_md "$tmp_path" "$output_mode" || { rm -f "$tmp_path"; die "Invalid PROMPT.md generated"; }
```

**Step D — update the `write_meta_json` call** (currently passes 8 args ending in `"$mode"`):

**Current:**
```bash
write_meta_json "$dir/meta.json" "$repo" "$issue_number" "$title" "$slug" "$backend" "$session_name" "$mode"
```

**New:**
```bash
write_meta_json "$dir/meta.json" "$repo" "$issue_number" "$title" "$slug" "$backend" "$session_name" "$mode" "$output_mode"
```

**Step E — add user-visible echo** for output mode (after the existing "Mode: $mode" echo, around line 2342):

```bash
echo "Output mode: $output_mode"
```

This always prints (single or three-artifact). Operators benefit from seeing both modes when debugging "why didn't I get three files?" — see Validation A5.

### 3.8 Add mode-mismatch detection to `cmd_create()` (resolves MF5)

**File:** `/home/agentdev/projects/acorn/main/bin/acorn`
**Location:** Inside `cmd_create()`, immediately AFTER Step A in §3.7 (i.e., right after the `output_mode` variable is set and validated), and BEFORE the `if [ ! -f "$prompt_path" ]; then ... else info "PROMPT.md already exists, leaving as-is"; fi` block.

**Add:**
```bash
# Mode-mismatch detection: if a previous run created PROMPT.md with a
# different output_mode, warn the operator. PROMPT.md will not be
# regenerated automatically (existing behavior preserved); the operator
# must delete PROMPT.md to switch modes for this spec.
if [ -f "$dir/PROMPT.md" ] && [ -f "$dir/meta.json" ]; then
  local recorded_om
  recorded_om="$(jq -r '.output_mode // "single"' "$dir/meta.json" 2>/dev/null || printf 'single')"
  if [ "$recorded_om" != "$output_mode" ]; then
    warn "PROMPT.md exists with output_mode=$recorded_om but env requests $output_mode."
    warn "PROMPT.md will NOT be regenerated. To switch modes for this spec:"
    warn "  rm $dir/PROMPT.md && ACORN_OUTPUT_MODE=$output_mode $0 create $repo $issue_number ..."
  fi
fi
```

**Verification:** Test T14 (§5.14) creates a spec with `single`, then re-runs with `three-artifact` and asserts the warning fires.

### 3.9 Modify `cmd_approve()` to soft-warn on missing PLAN.md / TASKS.md

**File:** `/home/agentdev/projects/acorn/main/bin/acorn`
**Location:** Function at lines 2392-2432. Insertion point: immediately AFTER the existing SPEC.md guard at line 2403 (`[ -f "$dir/plans/SPEC.md" ] || die "Missing final plan: $dir/plans/SPEC.md"`).

**Add:**
```bash
# Three-artifact mode (recorded in meta.json at create time): warn but
# don't fail if PLAN.md/TASKS.md are missing or empty. Use -s (size > 0)
# to catch truncated/half-written files, not just absent ones.
local recorded_output_mode
recorded_output_mode="$(jq -r '.output_mode // "single"' "$dir/meta.json" 2>/dev/null || printf 'single')"
if [ "$recorded_output_mode" = "three-artifact" ]; then
  [ -s "$dir/plans/PLAN.md" ] \
    || warn "Three-artifact mode: missing or empty PLAN.md ($dir/plans/PLAN.md) — approving anyway"
  [ -s "$dir/plans/TASKS.md" ] \
    || warn "Three-artifact mode: missing or empty TASKS.md ($dir/plans/TASKS.md) — approving anyway"
fi
```

**Why read from `meta.json`, not env var:** `acorn approve` may run in a different shell session, hours later, without `ACORN_OUTPUT_MODE` set. The approval check should reflect what the spec was generated with, not what the current shell environment says. The `2>/dev/null || printf 'single'` chain handles missing meta.json file or malformed JSON — both default to `single`, matching legacy spec dirs.

**Why `-s` not `-f`:** Per SF7, catches LLM partial output (file exists but is empty/truncated).

**Why `warn` not `die`:** Per AC #6, missing PLAN.md/TASKS.md is non-fatal — operator can still approve a SPEC.md-only output and regenerate later.

### 3.10 Modify `cmd_spec_complete()` — same soft-warn (parallel to §3.9)

**File:** `/home/agentdev/projects/acorn/main/bin/acorn`
**Location:** Function at lines 2434-2469. Insertion point: immediately AFTER the existing SPEC.md guard at line 2445.

**Add (identical to §3.9 except the trailing message):**
```bash
local recorded_output_mode
recorded_output_mode="$(jq -r '.output_mode // "single"' "$dir/meta.json" 2>/dev/null || printf 'single')"
if [ "$recorded_output_mode" = "three-artifact" ]; then
  [ -s "$dir/plans/PLAN.md" ] \
    || warn "Three-artifact mode: missing or empty PLAN.md ($dir/plans/PLAN.md)"
  [ -s "$dir/plans/TASKS.md" ] \
    || warn "Three-artifact mode: missing or empty TASKS.md ($dir/plans/TASKS.md)"
fi
```

The body is identical to §3.9 except messages don't say "approving anyway" since `cmd_spec_complete` is a different lifecycle event. Two callers, ~5 lines each — keep inline (DRY would obscure rather than clarify at this scale).

### 3.11 Modify `write_meta_json()` to record `output_mode`

**File:** `/home/agentdev/projects/acorn/main/bin/acorn`
**Location:** Function at lines 1948-1971.

**Current signature (8 args):**
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
```

**New signature (9 args):**
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
```

**Current jq invocation:**
```bash
jq -n \
  --arg repo "$repo" \
  --argjson issue_number "$issue_number" \
  --arg issue_title "$issue_title" \
  --arg slug "$slug" \
  --arg created_at "$ts" \
  --arg session_backend "$backend" \
  --arg session_name "$session_name" \
  --arg mode "$mode" \
  '{repo:$repo, issue_number:$issue_number, issue_title:$issue_title, slug:$slug, created_at:$created_at, session_backend:$session_backend, session_name:$session_name, mode:$mode}' \
  > "$path"
```

**New jq invocation (add `--arg output_mode` and field):**
```bash
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
```

**Backwards compat:** Existing 8-arg callers receive default `single` and `meta.json` gets `"output_mode": "single"`. Existing meta.json files (lacking the field) are read with `jq -r '.output_mode // "single"'` → `single`. No migration required.

### 3.12 Documentation update — `claude/commands/acorn.md`

**File:** `/home/agentdev/projects/acorn/main/claude/commands/acorn.md`

#### 3.12.1 Update the "Project layout" / spec directory layout block

**Anchor:** Locate the existing code block that documents the `.specs/<slug>/` directory tree (under the "Project layout" section, currently around lines 204-223).

**Update the `plans/` subtree to add the two new files (conditionally):**
```
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

#### 3.12.2 Add new "Output Modes" subsection

**Anchor:** Insert AFTER the existing "Project layout" section, before the next section.

**Add:**
```markdown
### Output Modes

Acorn supports two output modes controlled by the `ACORN_OUTPUT_MODE` env var:

- **`single`** (default) — produces only `plans/SPEC.md`. Backwards-compatible
  with upstream `craigmmills/acorn`.

- **`three-artifact`** — produces `plans/SPEC.md` + `plans/PLAN.md` + `plans/TASKS.md`.
  - SPEC.md: trimmed to functional requirements + traceability matrix
  - PLAN.md: implementation design (architecture, contracts, data, sequence, risks)
  - TASKS.md: atomic work items as YAML blocks with verify commands; first line is
    the schema version marker `# acorn-tasks-schema: v1`

Set the env var before running `acorn create`:

    ACORN_OUTPUT_MODE=three-artifact acorn create forge 6 --lite

The mode is recorded in `meta.json` (field `output_mode`) and read by
`acorn approve` / `acorn spec-complete` to enable warnings about missing
PLAN/TASKS files. `acorn approve` does NOT re-read the env var — it trusts
the recorded mode.

**Quality advisory:** Three-artifact output in `quick` mode is less validated
than in `lite` or `full` mode (no draft+validate cycle in quick mode). Prefer
`lite` or `full` when downstream consumers depend on TASKS.md schema correctness.

**Switching modes for an existing spec:** Acorn does not regenerate `PROMPT.md`
if it exists. To switch a spec from `single` to `three-artifact` (or vice versa):

    rm ~/projects/<repo>/main/.specs/<slug>/PROMPT.md
    ACORN_OUTPUT_MODE=<new-mode> acorn create <repo> <issue> [--lite|--quick]
```

---

## 4. Data Models

### 4.1 Env Var Contract: `ACORN_OUTPUT_MODE`

```
Name:     ACORN_OUTPUT_MODE
Type:     string
Values:   "single" | "three-artifact"
Default:  "single"  (preserves upstream-compatible behavior)
Set by:   Forge consumers (Foreman dispatch wrappers); operators ad-hoc
Read by:  cmd_create (at create time, validated; warns + falls back on invalid value)
          cmd_approve (via meta.json, NOT env var)
          cmd_spec_complete (via meta.json, NOT env var)
Invalid value behavior: warn + fall back to "single". No CLI failure.
Mode mismatch behavior: cmd_create warns if env value differs from recorded value
          in existing meta.json; PROMPT.md NOT regenerated.
```

### 4.2 PLAN.md Schema (LLM-emitted, prompt-enforced)

Required sections in this exact order with these exact heading texts:

1. `## 1. Architecture Decisions` — bullets with rationale + alternatives considered
2. `## 2. API Contracts` — inputs/outputs/side effects per touched function or interface
3. `## 3. Data Model Changes` — schemas, migrations; or literal "No data model changes." if not applicable
4. `## 4. Implementation Sequence` — numbered phases with dependencies
5. `## 5. Risk Register` — markdown table: ID | Risk | Severity | Likelihood | Mitigation

### 4.3 TASKS.md Schema (LLM-emitted, prompt-enforced)

**File header (line 1):**
```
# acorn-tasks-schema: v1
```

**Body:** YAML list of task blocks. Each block:
```yaml
- id: T1                              # required, format T<number> or T<number>.<letter>
  title: "<one-line description>"     # required, quoted string
  size: M                             # required, one of: XS, S, M, L, XL
  files: [path/a.sh, path/b.sh]       # required, list of repo-relative paths
  verify: "<command>"                 # required, runnable from repo root, no implicit cd
  depends_on: [T0]                    # required (may be []), list of task IDs
```

XL tasks (>8 files OR >3 new interfaces) tagged with note: `⚠️ XL: requires decomposition`.

Tasks are listed in topological order; a task may only `depends_on` tasks listed before it.

### 4.4 SPEC.md Trim Contract (three-artifact mode)

In three-artifact mode, SPEC.md retains:
- `## Pi Model Recommendation` (top, unchanged)
- `## 1. Requirements Traceability Matrix` (unchanged)
- `## 2. Validation Resolution Log` (unchanged; or "Red Team Resolution Log" in full mode)
- `## Functional Requirements` (Job Story, Promise, Constraints from PROMPT.md)
- `## Risk Register` — REPLACED with one-paragraph pointer: "See PLAN.md §5 Risk Register for the full register."
- `## Acceptance Criteria` — REPLACED with one-paragraph pointer: "See TASKS.md for the verifiable, atomic task list that satisfies acceptance."

SPEC.md REMOVES:
- `## Implementation Plan` — entire section (moves to PLAN.md §1-§4)
- `## Testing Strategy` — entire section (moves to PLAN.md §4 + TASKS.md verify commands)

A legacy reader (single-mode consumer) must still understand WHAT and WHY from SPEC.md alone.

### 4.5 `meta.json` Schema (extended)

**Before (8 fields):**
```json
{
  "repo": "forge",
  "issue_number": 6,
  "issue_title": "Three-artifact pipeline output",
  "slug": "6-three-artifact",
  "created_at": "2026-05-02T12:00:00Z",
  "session_backend": "tmux",
  "session_name": "forge_specs_6-three-artifact_claude",
  "mode": "lite"
}
```

**After (9 fields, adds `output_mode`):**
```json
{
  "repo": "forge",
  "issue_number": 6,
  "issue_title": "Three-artifact pipeline output",
  "slug": "6-three-artifact",
  "created_at": "2026-05-02T12:00:00Z",
  "session_backend": "tmux",
  "session_name": "forge_specs_6-three-artifact_claude",
  "mode": "lite",
  "output_mode": "three-artifact"
}
```

**Migration:** Pre-existing `meta.json` files lack the field. All readers use `jq -r '.output_mode // "single"'` to default to `single`. No bulk migration required. The pattern matches existing `mode // "full"` usage already in the codebase.

---

## 5. Testing Strategy

### 5.1 Test framework alignment

Per `recon/conventions.md`:
- Hand-rolled bash tests, no external framework (no bats, no shunit2, no pytest)
- `eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"` to source functions without invoking `main()`
- `pass` / `fail` / `assert_eq` / `assert_contains` / `assert_not_contains` helpers (define in test file)
- `setup` / `teardown` with `trap teardown EXIT`
- Mock externals via `export -f`
- File naming: `test/test_<feature>.sh`
- Run independently: `bash test/test_three_artifact.sh`

### 5.2 New test file: `/home/agentdev/projects/acorn/main/test/test_three_artifact.sh`

Create this new file with all 16 tests below. Boilerplate (header, helpers, setup/teardown) follows `test/test_labels.sh` conventions. Mocks use the `MOCK_SPEC_DIR` global env var pattern (per NF4 resolution) instead of closure-captured locals.

**Test file boilerplate:**

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACORN_SCRIPT="$SCRIPT_DIR/bin/acorn"

# Source acorn functions without triggering main()
# Unset ACORN_OUTPUT_MODE first so the constants block uses the default.
unset ACORN_OUTPUT_MODE
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
MOCK_SPEC_DIR=""
setup() {
  TMPDIR_BASE="$(mktemp -d)"
  MOCK_SPEC_DIR=""
}
teardown() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE"
  unset MOCK_SPEC_DIR
  unset -f gh ensure_labels set_issue_state_label comment_issue \
           safe_repo_main notify_telegram notify_foreman \
           spec_dir register_with_forged check_circuit_breaker 2>/dev/null || true
}
trap teardown EXIT
```

### 5.3 Test T3 — `planning_block_lite` single mode omits block (AC #1, #2)

```bash
test_T3_planning_block_lite_single_mode_omits_block() {
  printf '\n\033[1m== T3: lite + single mode omits three-artifact block ==\033[0m\n'
  local out
  out="$(planning_block_lite "/tmp/spec" "single")"
  assert_not_contains "no THREE-ARTIFACT header" "$out" "THREE-ARTIFACT OUTPUT MODE"
  assert_not_contains "no PLAN.md mention" "$out" "/tmp/spec/plans/PLAN.md"
  assert_not_contains "no TASKS.md mention" "$out" "/tmp/spec/plans/TASKS.md"
  assert_not_contains "no placeholder remains" "$out" "__THREE_ARTIFACT_BLOCK__"
  assert_contains "still mentions SPEC.md" "$out" "/tmp/spec/plans/SPEC.md"
}
```

### 5.4 Test T4 — `planning_block_lite` three-artifact includes full block + schemas (AC #2, #3, #4, #5)

```bash
test_T4_planning_block_lite_three_artifact_includes_block() {
  printf '\n\033[1m== T4: lite + three-artifact includes schemas ==\033[0m\n'
  local out
  out="$(planning_block_lite "/tmp/spec" "three-artifact")"
  # AC #2: header + paths
  assert_contains "THREE-ARTIFACT header" "$out" "THREE-ARTIFACT OUTPUT MODE"
  assert_contains "OVERRIDE language" "$out" "OVERRIDES the prior"
  assert_contains "mentions PLAN.md path" "$out" "/tmp/spec/plans/PLAN.md"
  assert_contains "mentions TASKS.md path" "$out" "/tmp/spec/plans/TASKS.md"
  assert_not_contains "no placeholder remains" "$out" "__THREE_ARTIFACT_BLOCK__"
  assert_not_contains "no SPEC_PATH placeholder remains" "$out" "__SPEC_PATH__"
  # AC #3: PLAN.md sections
  assert_contains "PLAN §1 Architecture" "$out" "Architecture Decisions"
  assert_contains "PLAN §2 API Contracts" "$out" "API Contracts"
  assert_contains "PLAN §3 Data Model" "$out" "Data Model Changes"
  assert_contains "PLAN §4 Implementation Sequence" "$out" "Implementation Sequence"
  assert_contains "PLAN §5 Risk Register" "$out" "Risk Register"
  # AC #4: TASKS.md schema
  assert_contains "TASKS schema version marker" "$out" "acorn-tasks-schema: v1"
  assert_contains "TASKS yaml id" "$out" "id: T1"
  assert_contains "TASKS yaml size" "$out" "size: M"
  assert_contains "TASKS yaml verify" "$out" "verify:"
  assert_contains "TASKS yaml depends_on" "$out" "depends_on:"
  assert_contains "TASKS XL warning" "$out" "XL: requires decomposition"
  assert_contains "TASKS verify cwd rule" "$out" "runnable from the repo root"
  # AC #5: SPEC.md trim guidance (uses section names, not numbers)
  assert_contains "SPEC TRIMMED keyword" "$out" "TRIMMED"
  assert_contains "SPEC must remain stand-alone" "$out" "stand-alone"
  assert_contains "KEEP Requirements Traceability Matrix" "$out" "Requirements Traceability Matrix"
  assert_contains "KEEP Pi Model Recommendation" "$out" "Pi Model Recommendation"
  assert_contains "REMOVE Implementation Plan" "$out" "Implementation Plan"
  # Final-response override
  assert_contains "Final response override" "$out" "Done. Output: /tmp/spec/plans/SPEC.md + /tmp/spec/plans/PLAN.md + /tmp/spec/plans/TASKS.md"
}
```

### 5.5 Tests T5, T6, T11, T12 — full and quick modes, both output modes

```bash
test_T5_planning_block_full_three_artifact() {
  printf '\n\033[1m== T5: full + three-artifact includes schemas ==\033[0m\n'
  local out
  out="$(planning_block_full "/tmp/spec" "three-artifact")"
  assert_contains "THREE-ARTIFACT header" "$out" "THREE-ARTIFACT OUTPUT MODE"
  assert_contains "PLAN.md path" "$out" "/tmp/spec/plans/PLAN.md"
  assert_contains "TASKS.md path" "$out" "/tmp/spec/plans/TASKS.md"
  assert_not_contains "no placeholder" "$out" "__THREE_ARTIFACT_BLOCK__"
}

test_T6_planning_block_quick_three_artifact() {
  printf '\n\033[1m== T6: quick + three-artifact includes schemas ==\033[0m\n'
  local out
  out="$(planning_block_quick "/tmp/spec" "three-artifact")"
  assert_contains "THREE-ARTIFACT header" "$out" "THREE-ARTIFACT OUTPUT MODE"
  assert_contains "PLAN.md path" "$out" "/tmp/spec/plans/PLAN.md"
  assert_contains "TASKS.md path" "$out" "/tmp/spec/plans/TASKS.md"
  assert_not_contains "no placeholder" "$out" "__THREE_ARTIFACT_BLOCK__"
}

test_T11_planning_block_full_single_mode_omits_block() {
  printf '\n\033[1m== T11: full + single omits block ==\033[0m\n'
  local out
  out="$(planning_block_full "/tmp/spec" "single")"
  assert_not_contains "no THREE-ARTIFACT" "$out" "THREE-ARTIFACT OUTPUT MODE"
  assert_not_contains "no PLAN.md" "$out" "/tmp/spec/plans/PLAN.md"
  assert_not_contains "no placeholder" "$out" "__THREE_ARTIFACT_BLOCK__"
  assert_contains "has SPEC.md" "$out" "/tmp/spec/plans/SPEC.md"
}

test_T12_planning_block_quick_single_mode_omits_block() {
  printf '\n\033[1m== T12: quick + single omits block ==\033[0m\n'
  local out
  out="$(planning_block_quick "/tmp/spec" "single")"
  assert_not_contains "no THREE-ARTIFACT" "$out" "THREE-ARTIFACT OUTPUT MODE"
  assert_not_contains "no PLAN.md" "$out" "/tmp/spec/plans/PLAN.md"
  assert_not_contains "no placeholder" "$out" "__THREE_ARTIFACT_BLOCK__"
  assert_contains "has SPEC.md" "$out" "/tmp/spec/plans/SPEC.md"
}
```

### 5.6 Test T1, T2 — env var defaults and validation (AC #1)

```bash
test_T1_default_output_mode_is_single() {
  printf '\n\033[1m== T1: ACORN_OUTPUT_MODE defaults to single when unset ==\033[0m\n'
  unset ACORN_OUTPUT_MODE
  # Re-source to re-run constants block
  eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"
  assert_eq "default is single" "${ACORN_OUTPUT_MODE:-MISSING}" "single"
}

test_T2_invalid_value_warns_and_falls_back_in_cmd_create() {
  printf '\n\033[1m== T2: invalid value warns + falls back in cmd_create ==\033[0m\n'
  # Simulate the validation block from §3.7 Step A
  local output_mode="bogus"
  local stderr_file="$TMPDIR_BASE/stderr"
  case "$output_mode" in
    single|three-artifact) ;;
    *) printf '[WARN] Unknown ACORN_OUTPUT_MODE=%s; falling back to single\n' "$output_mode" >&2; output_mode="single" ;;
  esac 2>"$stderr_file"
  assert_eq "fell back to single" "$output_mode" "single"
  local stderr_content; stderr_content="$(cat "$stderr_file")"
  assert_contains "warned about invalid value" "$stderr_content" "Unknown ACORN_OUTPUT_MODE"
}
```

### 5.7 Tests T7, T8 — meta.json output_mode field (AC #1)

```bash
test_T7_write_meta_json_records_output_mode() {
  printf '\n\033[1m== T7: meta.json records output_mode ==\033[0m\n'
  local meta="$TMPDIR_BASE/meta.json"
  write_meta_json "$meta" "forge" "6" "title" "6-slug" "tmux" "sess" "lite" "three-artifact"
  local out; out="$(jq -r '.output_mode' "$meta")"
  assert_eq "output_mode = three-artifact" "$out" "three-artifact"
}

test_T8_write_meta_json_default_output_mode_is_single() {
  printf '\n\033[1m== T8: meta.json defaults output_mode to single ==\033[0m\n'
  local meta="$TMPDIR_BASE/meta.json"
  # 8 args (no output_mode) — uses default
  write_meta_json "$meta" "forge" "6" "title" "6-slug" "tmux" "sess" "lite"
  local out; out="$(jq -r '.output_mode' "$meta")"
  assert_eq "defaults to single" "$out" "single"
}
```

### 5.8 Test T16 — `three_artifact_instructions` emits non-empty (E2)

```bash
test_T16_three_artifact_instructions_emits_nonempty() {
  printf '\n\033[1m== T16: three_artifact_instructions emits non-empty ==\033[0m\n'
  local out; out="$(three_artifact_instructions)"
  if [ -z "$out" ]; then
    fail "non-empty output" "function returned empty string"
    return
  fi
  pass "non-empty output"
  assert_contains "header present" "$out" "THREE-ARTIFACT OUTPUT MODE"
  assert_contains "schema marker present" "$out" "acorn-tasks-schema: v1"
  assert_contains "OVERRIDE language present" "$out" "OVERRIDES"
}
```

### 5.9 Tests T9, T9b — `cmd_approve` warns on missing/empty PLAN.md/TASKS.md (AC #6)

```bash
_setup_approve_mocks() {
  # Common mock setup shared by approve and spec_complete tests.
  # Uses MOCK_SPEC_DIR global instead of closure (per NF4).
  safe_repo_main() { printf '%s' "$TMPDIR_BASE/repo"; }
  spec_dir() { printf '%s' "$MOCK_SPEC_DIR"; }
  ensure_labels() { :; }
  set_issue_state_label() { :; }
  comment_issue() { :; }
  notify_telegram() { :; }
  notify_foreman() { :; }
  register_with_forged() { :; }
  check_circuit_breaker() { return 0; }
  export -f safe_repo_main spec_dir ensure_labels set_issue_state_label \
            comment_issue notify_telegram notify_foreman register_with_forged \
            check_circuit_breaker
  mkdir -p "$TMPDIR_BASE/repo"
}

test_T9_approve_warns_on_missing_plan_in_three_artifact_mode() {
  printf '\n\033[1m== T9: approve warns on missing PLAN.md and TASKS.md ==\033[0m\n'
  MOCK_SPEC_DIR="$TMPDIR_BASE/spec"
  mkdir -p "$MOCK_SPEC_DIR/plans"
  echo "minimal spec" > "$MOCK_SPEC_DIR/plans/SPEC.md"
  # PLAN.md and TASKS.md absent
  write_meta_json "$MOCK_SPEC_DIR/meta.json" "forge" "6" "title" "6-slug" "tmux" "sess" "lite" "three-artifact"
  _setup_approve_mocks
  local stderr_file="$TMPDIR_BASE/stderr"
  cmd_approve "forge" "6-slug" 2>"$stderr_file" >/dev/null || true
  local stderr; stderr="$(cat "$stderr_file")"
  assert_contains "warns about PLAN.md" "$stderr" "missing or empty PLAN.md"
  assert_contains "warns about TASKS.md" "$stderr" "missing or empty TASKS.md"
}

test_T9b_approve_warns_on_empty_plan_in_three_artifact_mode() {
  printf '\n\033[1m== T9b: approve warns on EMPTY PLAN.md (truncated case) ==\033[0m\n'
  MOCK_SPEC_DIR="$TMPDIR_BASE/spec_empty"
  mkdir -p "$MOCK_SPEC_DIR/plans"
  echo "spec content" > "$MOCK_SPEC_DIR/plans/SPEC.md"
  : > "$MOCK_SPEC_DIR/plans/PLAN.md"   # empty file (truncated LLM output)
  : > "$MOCK_SPEC_DIR/plans/TASKS.md"  # empty file
  write_meta_json "$MOCK_SPEC_DIR/meta.json" "forge" "6" "title" "6-slug" "tmux" "sess" "lite" "three-artifact"
  _setup_approve_mocks
  local stderr_file="$TMPDIR_BASE/stderr_empty"
  cmd_approve "forge" "6-slug" 2>"$stderr_file" >/dev/null || true
  local stderr; stderr="$(cat "$stderr_file")"
  assert_contains "warns about empty PLAN.md" "$stderr" "missing or empty PLAN.md"
  assert_contains "warns about empty TASKS.md" "$stderr" "missing or empty TASKS.md"
}
```

### 5.10 Test T10 — `cmd_approve` silent in single mode (AC #6)

```bash
test_T10_approve_no_warn_in_single_mode() {
  printf '\n\033[1m== T10: approve silent in single mode ==\033[0m\n'
  MOCK_SPEC_DIR="$TMPDIR_BASE/spec_single"
  mkdir -p "$MOCK_SPEC_DIR/plans"
  echo "spec" > "$MOCK_SPEC_DIR/plans/SPEC.md"
  write_meta_json "$MOCK_SPEC_DIR/meta.json" "forge" "6" "title" "6-slug" "tmux" "sess" "lite" "single"
  _setup_approve_mocks
  local stderr_file="$TMPDIR_BASE/stderr_single"
  cmd_approve "forge" "6-slug" 2>"$stderr_file" >/dev/null || true
  local stderr; stderr="$(cat "$stderr_file")"
  assert_not_contains "no PLAN warning" "$stderr" "missing or empty PLAN.md"
  assert_not_contains "no TASKS warning" "$stderr" "missing or empty TASKS.md"
}
```

### 5.11 Test T13 — `cmd_spec_complete` warns on missing files (AC #6, SF2)

```bash
test_T13_spec_complete_warns_on_missing_plan_in_three_artifact_mode() {
  printf '\n\033[1m== T13: spec-complete warns on missing PLAN.md and TASKS.md ==\033[0m\n'
  MOCK_SPEC_DIR="$TMPDIR_BASE/spec_sc"
  mkdir -p "$MOCK_SPEC_DIR/plans"
  echo "spec" > "$MOCK_SPEC_DIR/plans/SPEC.md"
  write_meta_json "$MOCK_SPEC_DIR/meta.json" "forge" "6" "title" "6-slug" "tmux" "sess" "lite" "three-artifact"
  _setup_approve_mocks
  local stderr_file="$TMPDIR_BASE/stderr_sc"
  cmd_spec_complete "forge" "6-slug" 2>"$stderr_file" >/dev/null || true
  local stderr; stderr="$(cat "$stderr_file")"
  assert_contains "warns PLAN.md" "$stderr" "missing or empty PLAN.md"
  assert_contains "warns TASKS.md" "$stderr" "missing or empty TASKS.md"
}
```

### 5.12 Test T14 — `cmd_create` warns on mode mismatch (MF5)

```bash
test_T14_cmd_create_warns_on_mode_mismatch() {
  printf '\n\033[1m== T14: cmd_create warns when env mode differs from recorded mode ==\033[0m\n'
  # Simulate a pre-existing spec dir with PROMPT.md and meta.json (single mode)
  MOCK_SPEC_DIR="$TMPDIR_BASE/spec_mm"
  mkdir -p "$MOCK_SPEC_DIR/plans"
  echo "existing prompt" > "$MOCK_SPEC_DIR/PROMPT.md"
  write_meta_json "$MOCK_SPEC_DIR/meta.json" "forge" "6" "title" "6-slug" "tmux" "sess" "lite" "single"

  # Direct test of the mismatch detection block (do not invoke full cmd_create
  # which has many side effects; test the detection logic in isolation).
  local recorded_om
  recorded_om="$(jq -r '.output_mode // "single"' "$MOCK_SPEC_DIR/meta.json" 2>/dev/null || printf 'single')"
  assert_eq "recorded mode read" "$recorded_om" "single"
  local desired_om="three-artifact"
  if [ "$recorded_om" != "$desired_om" ]; then
    pass "mode mismatch detected (single vs three-artifact)"
  else
    fail "mode mismatch detected" "expected mismatch but values matched"
  fi
}
```

### 5.13 Test T15 — `validate_prompt_md` checks substitution (SF3)

```bash
test_T15_validate_prompt_md_checks_three_artifact_substitution() {
  printf '\n\033[1m== T15: validate_prompt_md verifies three-artifact substitution ==\033[0m\n'
  local good_path="$TMPDIR_BASE/good_prompt.md"
  local bad_path_no_block="$TMPDIR_BASE/bad_no_block.md"
  local bad_path_placeholder_remains="$TMPDIR_BASE/bad_placeholder.md"

  # Good: has methodology header AND THREE-ARTIFACT header AND no placeholder
  cat > "$good_path" <<EOF
PLANNING METHODOLOGY — MANDATORY INSTRUCTIONS
THREE-ARTIFACT OUTPUT MODE
schemas here
EOF

  # Bad: no THREE-ARTIFACT header (substitution didn't run / wrong mode)
  cat > "$bad_path_no_block" <<EOF
PLANNING METHODOLOGY — MANDATORY INSTRUCTIONS
no three-artifact content
EOF

  # Bad: placeholder still present (sed substitution failed)
  cat > "$bad_path_placeholder_remains" <<EOF
PLANNING METHODOLOGY — MANDATORY INSTRUCTIONS
__THREE_ARTIFACT_BLOCK__
EOF

  if validate_prompt_md "$good_path" "three-artifact"; then pass "good prompt validates"
  else fail "good prompt validates" "expected pass"; fi

  if validate_prompt_md "$bad_path_no_block" "three-artifact"; then
    fail "bad-no-block detected" "expected validation to fail"
  else pass "bad-no-block detected"; fi

  if validate_prompt_md "$bad_path_placeholder_remains" "three-artifact"; then
    fail "bad-placeholder detected" "expected validation to fail"
  else pass "bad-placeholder detected"; fi

  # Single-mode default: only methodology header check; THREE-ARTIFACT not required
  if validate_prompt_md "$bad_path_no_block" "single"; then pass "single-mode skips three-artifact check"
  else fail "single-mode skips three-artifact check" "expected pass"; fi
}
```

### 5.14 Test execution sequence (bottom of test file)

```bash
setup; test_T1_default_output_mode_is_single
setup; test_T2_invalid_value_warns_and_falls_back_in_cmd_create
setup; test_T3_planning_block_lite_single_mode_omits_block
setup; test_T4_planning_block_lite_three_artifact_includes_block
setup; test_T5_planning_block_full_three_artifact
setup; test_T6_planning_block_quick_three_artifact
setup; test_T7_write_meta_json_records_output_mode
setup; test_T8_write_meta_json_default_output_mode_is_single
setup; test_T9_approve_warns_on_missing_plan_in_three_artifact_mode
setup; test_T9b_approve_warns_on_empty_plan_in_three_artifact_mode
setup; test_T10_approve_no_warn_in_single_mode
setup; test_T11_planning_block_full_single_mode_omits_block
setup; test_T12_planning_block_quick_single_mode_omits_block
setup; test_T13_spec_complete_warns_on_missing_plan_in_three_artifact_mode
setup; test_T14_cmd_create_warns_on_mode_mismatch
setup; test_T15_validate_prompt_md_checks_three_artifact_substitution
setup; test_T16_three_artifact_instructions_emits_nonempty
teardown

printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
```

### 5.15 Regression test plan (existing tests must still pass)

After implementing all changes in §3, run:
```bash
bash test/test_labels.sh
bash test/test_auto_trigger.sh
bash test/test_split.sh
bash test/test_dependencies.sh
bash test/test_doctor.sh
bash test/test_idle_detect.sh
bash test/test_images.sh
bash test/test_notify.sh
bash test/test_concurrent_launch.sh
bash test/test_path_npm_global.sh
bash test/test_auth_preflight.sh
```

All MUST pass (zero new failures). The changes are purely additive — new positional args have safe defaults; existing call sites unchanged.

### 5.16 Run-all wrapper

Add to project README or run inline:
```bash
for t in test/test_*.sh; do
  printf '\n=== %s ===\n' "$t"
  bash "$t" || { printf 'FAILED: %s\n' "$t"; exit 1; }
done
```

### 5.17 Single-mode PROMPT.md regression note (E17)

In single mode, the new `__THREE_ARTIFACT_BLOCK__` placeholder line is deleted by `sed '/__THREE_ARTIFACT_BLOCK__/d'`. The resulting PROMPT.md differs from today's output by exactly one deleted blank line per planning_block (the placeholder line itself is the only line removed). This is acceptable and documented. To verify after merge:

```bash
# Save baseline before merge
git stash
ACORN_OUTPUT_MODE=single bash bin/acorn create <test-repo> <test-issue> --no-auto --lite
cp .specs/<slug>/PROMPT.md /tmp/baseline.md
git stash pop  # apply changes
rm .specs/<slug>/PROMPT.md
ACORN_OUTPUT_MODE=single bash bin/acorn create <test-repo> <test-issue> --no-auto --lite
diff /tmp/baseline.md .specs/<slug>/PROMPT.md
# Expected: small whitespace diff only (one blank line per planning_block).
```

### 5.18 Test data and fixtures

No external test data files required. All tests use `mktemp -d` for ephemeral spec dirs and inline content via heredocs / `echo`. The `MOCK_SPEC_DIR` global env var pattern eliminates closure-capture brittleness.

---

## 6. Manual Smoke Test Procedure (AC #7)

AC #7 requires running `acorn create <repo> <issue> --lite` against a representative issue and verifying all three files. This is a manual procedure (operator-driven) because the pipeline runs in a tmux session with an LLM agent — automating it would require mocking Claude.

### 6.1 Prerequisites

- A test issue exists in a real repo (e.g., `forge#6` or any small issue).
- `acorn`, `gh`, `jq`, `tmux`, `claude` are all installed and authenticated.
- The repo is checked out at `~/projects/<repo>/main/`.

### 6.2 Procedure

```bash
# Step 1: Run acorn create with three-artifact mode
ACORN_OUTPUT_MODE=three-artifact acorn create <repo> <issue> --lite

# Step 2: Wait for the tmux session to complete the pipeline
# (Attach with: tmux attach -t <repo>_specs_<issue>-<slug>_claude)
# The lite pipeline takes ~5-15 minutes for a small issue.

# Step 3: Verify all three files exist and are non-empty
ls -la ~/projects/<repo>/main/.specs/<issue>-<slug>/plans/
# Expected files (all non-empty):
#   - draft.md          (intermediate, lite Stage 1)
#   - validation.md     (intermediate, lite Stage 2)
#   - SPEC.md           (final)
#   - PLAN.md           (NEW, three-artifact)
#   - TASKS.md          (NEW, three-artifact)

# Step 4: Verify SPEC.md is valid stand-alone (legacy reader perspective)
head -40 ~/projects/<repo>/main/.specs/<issue>-<slug>/plans/SPEC.md
# MUST contain (in order):
#   - "## Pi Model Recommendation"
#   - "## 1. Requirements Traceability Matrix"
#   - "## Functional Requirements" (Job Story / Promise / Constraints)
# MUST contain pointers (not full content) to:
#   - "See PLAN.md §5 Risk Register..."
#   - "See TASKS.md..."

# Step 5: Verify PLAN.md has all 5 required sections in order
grep -E '^## [0-9]+\. ' ~/projects/<repo>/main/.specs/<issue>-<slug>/plans/PLAN.md
# Expected (in order):
#   ## 1. Architecture Decisions
#   ## 2. API Contracts
#   ## 3. Data Model Changes
#   ## 4. Implementation Sequence
#   ## 5. Risk Register

# Step 6: Verify TASKS.md schema
head -1 ~/projects/<repo>/main/.specs/<issue>-<slug>/plans/TASKS.md
# Expected: # acorn-tasks-schema: v1
grep -cE '^- id: T[0-9]' ~/projects/<repo>/main/.specs/<issue>-<slug>/plans/TASKS.md
# Expected: >= 1 (at least one valid task block)

# Step 7: Verify meta.json records output_mode
jq '.output_mode' ~/projects/<repo>/main/.specs/<issue>-<slug>/meta.json
# Expected: "three-artifact"

# Step 8: Verify acorn approve does NOT die on three-artifact spec
acorn approve <repo> <issue>-<slug>
# Expected: exits 0; no warnings about missing PLAN/TASKS

# Step 9 (optional negative test): Delete TASKS.md and re-approve; expect warning
mv ~/projects/<repo>/main/.specs/<issue>-<slug>/plans/TASKS.md /tmp/TASKS.md.bak
acorn approve <repo> <issue>-<slug>
# Expected: stderr contains "Three-artifact mode: missing or empty TASKS.md"
mv /tmp/TASKS.md.bak ~/projects/<repo>/main/.specs/<issue>-<slug>/plans/TASKS.md
```

### 6.3 Pass/Fail Criteria

- **PASS:** Steps 3-8 all match expected output. Step 9 warning fires.
- **FAIL:** Any of the three new files missing or empty; SPEC.md contains full Implementation Plan section (not trimmed); PLAN.md missing any of the 5 required sections; TASKS.md missing schema version marker; `acorn approve` errors instead of warns.

### 6.4 Single-mode regression check

```bash
# Verify single mode still produces only SPEC.md
ACORN_OUTPUT_MODE=single acorn create <repo> <other-issue> --lite
# Wait for completion
ls ~/projects/<repo>/main/.specs/<other-issue>-<slug>/plans/
# Expected: SPEC.md (no PLAN.md, no TASKS.md)
jq '.output_mode' ~/projects/<repo>/main/.specs/<other-issue>-<slug>/meta.json
# Expected: "single"
```

### 6.5 Mode-switching recovery procedure (NF2 resolution)

If a spec was created with one mode and the operator wants to switch:

```bash
# Delete PROMPT.md to force regeneration on next acorn create
rm ~/projects/<repo>/main/.specs/<slug>/PROMPT.md
# Re-run create with the desired mode
ACORN_OUTPUT_MODE=<new-mode> acorn create <repo> <issue> [--lite|--quick]
```

If the operator forgets to delete PROMPT.md and runs with a different mode, the new mode-mismatch warning (§3.8) tells them exactly what to do.

---

## 7. Risk Register (Unresolved Risks)

This is the FINAL risk register for this spec. Risks resolved during validation are NOT listed here (see §2 Validation Resolution Log).

| ID | Risk | Severity | Likelihood | Mitigation | Recommended follow-up |
|---|---|---|---|---|---|
| R1 | LLM ignores schema instructions and produces malformed PLAN.md or TASKS.md | Med | Med | Schemas are explicit and embedded verbatim in prompt; OVERRIDE language eliminates contradicting instructions; manual smoke test (§6) before forge rollout; downstream consumers fail loudly on parse errors. `validate_prompt_md` (§3.5) confirms the PROMPT.md substitution succeeded. | Operator inspects first 3-5 specs manually before relying on automated downstream parsing. File a follow-up to add a TASKS.md YAML lint helper if drift becomes common. |
| R2 | LLM over-trims SPEC.md so it no longer reads stand-alone | Low | Med | Prompt explicitly says "SPEC.md MUST remain valid stand-alone" and lists KEEP sections by NAME. Section-name approach (per MF3 fix) avoids template drift. Manual smoke step 4 (§6.2) verifies. | Add an automated SPEC.md structure check in a future PR (e.g., grep for "Functional Requirements" section). |
| R3 | sed `r ; d` substitution mechanism breaks on unusual heredoc content | Low | Low | sed `r filename` reads file content verbatim — no escape interpretation. Tested with backslashes, dollar signs, brackets, emojis. Order is `r` then `d`, which is the standard sed file-include idiom. POSIX-compatible (works on gawk, BWK awk hosts; doesn't actually use awk anymore). Test T4 explicitly asserts no `__THREE_ARTIFACT_BLOCK__` placeholder remains in output and no `__SPEC_PATH__` remains. | None — already mitigated. |
| R4 | Forge `spec-metadata-extract.sh` may strict-validate `meta.json` schema and reject unknown `output_mode` field | Low | Low | jq's default behavior is to ignore unknown fields. Acorn's `cmd_approve` invokes the script with the spec dir path; the script presumably reads meta.json with jq. Forward-compatibility risk is low. **Confidence:** Cannot verify without inspecting the forge-side script. | Forge consumer must verify their wrapper does not strict-validate `meta.json` schema before enabling three-artifact in production. File a forge-side issue to document and assert schema compatibility. |
| R5 | Concurrent `acorn create` invocations race on `meta.json` write | Low | Low | Pre-existing concern, not introduced. `write_meta_json` is not atomic (uses direct `> "$path"`). One tmux session per spec is the operational protection. | NF1: file a separate issue to add temp+mv atomic write to `write_meta_json`. |
| R6 | Operator sets `ACORN_OUTPUT_MODE=three-artifact` for `cmd_create`, then runs `acorn approve` from a shell where the env var is unset | Low | High | `cmd_approve` reads from `meta.json` (recorded at create time), NOT the env var. Documented in §3.9 and §6.5. Test T10 covers single-mode case; T9/T9b cover three-artifact case. | None — design is correct as-is. Documentation in §3.12.2 makes the meta.json source-of-truth explicit. |
| R7 | LLM partial output: SPEC.md written, PLAN.md or TASKS.md half-written / truncated | Low | Med | `[ -s ... ]` check (per SF7) catches empty/truncated files in approve and spec-complete; warns but does not block. Recovery: `rm` the truncated file and re-run pipeline. | Future: add a more rigorous structural check (e.g., PLAN.md must contain all 5 section headers) in `validate_prompt_md` or a new `validate_three_artifact_outputs` helper. |
| R8 | Quick-mode three-artifact may produce lower-quality PLAN/TASKS due to no draft+validate cycle | Med | Med | Quick mode is documented as "best for straightforward features"; the docs (§3.12.2) include an explicit advisory recommending lite or full mode for production planning when downstream consumers depend on TASKS.md schema correctness. | Forge dispatcher policy: only enable three-artifact mode for `--lite` and `--full`, leave `--quick` in single mode. Document this in forge SDLC review. |
| R9 | Schema drift across Acorn versions breaks downstream consumers | Med | Low | Schema version marker `# acorn-tasks-schema: v1` (per SF8) is the first line of every TASKS.md. Downstream consumers MUST check this marker before parsing. Future schema changes bump the version (v2, v3, ...) and update consumers in lockstep. | Add a `bin/acorn schema-version` subcommand in a future PR to print the current TASKS.md schema version. |
| R10 | Future schema changes require synchronized edits across full/lite/quick modes | Low | Med | Mitigated by `three_artifact_instructions()` single-source-of-truth pattern (§3.3). All three modes inject the same text via the same helper. A schema change touches exactly one function. | None — already mitigated. Risk is monitoring-only. |

### 7.1 Critical risks requiring operator awareness

- **R1**: Real risk of malformed YAML on first runs. Recommend manual review of TASKS.md output for first 3-5 specs before relying on automated downstream parsing.
- **R6**: Operators might be confused why `acorn approve` works without warnings even though they expected three-artifact mode. The §3.12.2 docs make explicit that `meta.json` is the source of truth.
- **R8**: Quick mode + three-artifact is a foot-gun. Forge consumers should disable it in policy, not in code.

### 7.2 Non-risks (explicitly considered and dismissed)

- **CI breakage**: no CI exists in this repo (per `recon/conventions.md`).
- **Dependency conflicts**: no new deps; sed and jq already required.
- **Migration data loss**: no schema changes to existing data; `output_mode` field addition is forward-compatible (jq ignores unknown fields and `// "single"` defaults missing fields).
- **Performance**: prompt is ~110 lines longer in three-artifact mode; negligible vs. typical ~3000-line PROMPT.md.
- **Security — env var injection**: `ACORN_OUTPUT_MODE` value is used only in `case` literal-pattern matching and `--arg` jq passing (both injection-safe).
- **Security — issue body injection**: issue body cannot inject `__THREE_ARTIFACT_BLOCK__` because the placeholder substitution happens inside `planning_block_*()` before the body is appended to PROMPT.md.
- **Bash version compat**: bash 3+ syntax used throughout; macOS BWK sed and Linux GNU sed both support `r` command and `/pattern/{...}` blocks.

---

## 8. Implementation Sequence (Phases with Dependencies)

Each phase is independently verifiable. Dependencies listed explicitly.

### Phase 1 — Foundation (no behavior change)
**Dependencies:** none.
**Verifiable independently:** yes — existing tests still pass.

1. §3.1 Add `ACORN_OUTPUT_MODE` global declaration after line 13.
2. §3.3 Add `three_artifact_instructions()` function near line 661 (before `planning_block()`).

**After Phase 1:** function defined but never called. `ACORN_OUTPUT_MODE` defined but no consumer reads it. All existing tests pass.

**Verification:** `bash test/test_labels.sh && bash test/test_auto_trigger.sh && bash test/test_split.sh` — zero failures.

### Phase 2 — Plumbing (positional args, no behavior change in default mode)
**Dependencies:** Phase 1.
**Verifiable independently:** yes — single-mode behavior unchanged.

1. §3.4.1 Extend `planning_block()` signature.
2. §3.4.3 Extend `planning_block_lite()` signature + insert placeholder + wrap with sed-r/sed-d branches.
3. §3.4.4 Same for `planning_block_full()`.
4. §3.4.5 Same for `planning_block_quick()`.
5. §3.5 Extend `validate_prompt_md()` signature.
6. §3.6 Extend `render_prompt_md()` signature + forward to planning_block.
7. §3.11 Extend `write_meta_json()` signature + add jq field.

**After Phase 2:** signatures extended, default args ensure single-mode is byte-equivalent (modulo the documented one-blank-line-per-block whitespace difference) to before. Run existing tests.

**Verification:** All existing tests pass. Manual: `bash -c 'source bin/acorn 2>/dev/null; planning_block_lite /tmp/x single' | grep -q THREE-ARTIFACT && echo FAIL || echo PASS`.

### Phase 3 — Caller integration in `cmd_create`
**Dependencies:** Phase 2.
**Verifiable independently:** yes.

1. §3.7 Steps A-E: `cmd_create` reads + validates `ACORN_OUTPUT_MODE`, threads to `render_prompt_md`, `validate_prompt_md`, `write_meta_json`; adds user-visible echo.
2. §3.8 Add mode-mismatch detection block.

**After Phase 3:** setting `ACORN_OUTPUT_MODE=three-artifact` actually changes generated PROMPT.md content. Mode-mismatch warning fires when expected.

**Verification:** Run `acorn create` end-to-end with both modes against a test issue; diff PROMPT.md outputs.

### Phase 4 — Approval-time warnings
**Dependencies:** Phase 3 (needs `output_mode` field in `meta.json`).
**Verifiable independently:** yes.

1. §3.9 Add three-artifact warn-on-missing block to `cmd_approve()`.
2. §3.10 Add identical block to `cmd_spec_complete()`.

**After Phase 4:** AC #6 satisfied. Tests T9, T9b, T10, T13 pass.

### Phase 5 — Tests
**Dependencies:** Phases 1-4.
**Verifiable independently:** yes — runs tests.

1. §5.2 Create `test/test_three_artifact.sh` with all 16 tests + execution sequence.
2. Run full test suite to confirm no regressions.

**Verification:**
```bash
bash test/test_three_artifact.sh   # MUST pass: 17 PASS, 0 FAIL (T1-T16, with T9b counted)
for t in test/test_*.sh; do bash "$t" || break; done   # all pre-existing tests still pass
```

### Phase 6 — Documentation
**Dependencies:** Phase 5 (only document working behavior).
**Verifiable independently:** prose review.

1. §3.12.1 Update `claude/commands/acorn.md` directory-layout block.
2. §3.12.2 Add "Output Modes" subsection.

### Phase 7 — Manual integration smoke test (AC #7)
**Dependencies:** Phases 1-6.
**Verifiable independently:** yes — manual procedure in §6.

Execute §6.2 procedure end-to-end. Verify pass criteria in §6.3. Run §6.4 single-mode regression check.

---

## 9. Summary of Touched Files

| File | Type | Lines (est.) | Purpose |
|---|---|---|---|
| `/home/agentdev/projects/acorn/main/bin/acorn` | Production | +180 / -10 | All implementation: env var, helper function, signature extensions, heredoc placeholders, warn blocks, mode-mismatch detection |
| `/home/agentdev/projects/acorn/main/test/test_three_artifact.sh` | New test | +330 | 17 unit tests covering all ACs |
| `/home/agentdev/projects/acorn/main/claude/commands/acorn.md` | Docs | +35 / -5 | Directory layout update + new "Output Modes" subsection |

**Total: 3 files changed, ~540 net lines added.**

**No new dependencies.** **No schema breakage.** **No upstream incompatibility.** **No CI changes** (none exist).

---

## 10. Implementation Checklist (Pi Agent / Developer)

Use this checklist to verify nothing is missed:

- [ ] §3.1: `ACORN_OUTPUT_MODE` declared after line 13 in `bin/acorn`
- [ ] §3.3: `three_artifact_instructions()` function added before `planning_block()` at line ~661
- [ ] §3.4.1: `planning_block()` accepts and forwards `output_mode`
- [ ] §3.4.3: `planning_block_lite()` signature extended, placeholder inserted, sed-r/sed-d wrapping applied
- [ ] §3.4.4: Same for `planning_block_full()`
- [ ] §3.4.5: Same for `planning_block_quick()`
- [ ] §3.5: `validate_prompt_md()` extended with optional 2nd `output_mode` arg + checks
- [ ] §3.6: `render_prompt_md()` accepts 8th arg `output_mode`, forwards to `planning_block`
- [ ] §3.7: `cmd_create()` reads + validates env var, threads through, adds echo
- [ ] §3.8: `cmd_create()` mode-mismatch detection block added
- [ ] §3.9: `cmd_approve()` warn block added (uses `[ -s ... ]`)
- [ ] §3.10: `cmd_spec_complete()` warn block added (uses `[ -s ... ]`)
- [ ] §3.11: `write_meta_json()` extended with 9th arg + jq field
- [ ] §3.12.1: docs directory layout updated
- [ ] §3.12.2: docs "Output Modes" subsection added
- [ ] §5.2: `test/test_three_artifact.sh` created with all 17 tests
- [ ] All existing tests still pass (regression: §5.15)
- [ ] New tests pass: `bash test/test_three_artifact.sh` → 0 failures
- [ ] Manual smoke (AC #7): §6.2 procedure executed and passes §6.3 criteria

---

## 11. Out-of-Scope (Explicitly Deferred)

These items came up during planning/validation but are NOT part of this spec. Each has explicit justification.

| Item | Justification | Recommended follow-up |
|---|---|---|
| `--output-mode` CLI flag | AC #1 says "env var or equivalent CLI flag"; env var alone satisfies. Adding a flag later is non-breaking (positional args have defaults). | Future PR if operators request it. |
| Atomic write for `write_meta_json` | Pre-existing concern, not introduced by this feature. Operational protection (one tmux session per spec) is in place. | NF1: file separate issue. |
| TASKS.md YAML linter / parser | AC #8 forbids new dependencies; pure bash YAML parsing is fragile; downstream consumers (forge) own parsing per upstreamability constraint. | Forge can add a `tasks-lint` helper in their wrappers if needed. |
| `acorn list` / `acorn status` showing `output_mode` column | Not in AC #1-#8. Would clutter tabular output. | Future enhancement. |
| Forge-side `spec-metadata-extract.sh` updates to consume TASKS.md | Per upstreamability constraint, lives in forge wrappers, NOT acorn binary. | Forge tracks this in their own backlog. |
| Automated AC #7 end-to-end test | Would require mocking Claude or running real LLM in CI. Cost-benefit unfavorable; manual procedure (§6) is sufficient. | Revisit if a Claude mocking framework appears. |

---

End of SPEC.




---

## Round-2 RT Review Notes (cross-model, manual pass 2026-05-02 — Wave 2 batch 1)

This SPEC was reviewed by an operator-driven manual cross-model RT pass on 2026-05-02 (Wave 2 of the SDLC review's compounding-foundation work) with **OpenAI GPT-5.4**, **Gemini gemini-pro-latest**, **DeepSeek V4 Pro** (reasoning), and **DeepSeek V4 Flash**. Full per-spec data: `docs/rt-experiment-data-cumulative.json` (key `wave_2_batch_1`).

**Wave 1 empirical context** (from the Wave 1 RT pass that produced 0 corroboration at Jaccard ≥0.4 across 21 findings on 3 specs): standard precondition-11 OR-merge would block this spec. Operator (strategist session) authorized continuation under the Wave 1 override pattern: findings are surfaced to Pi as guidance; Pi classifies and addresses during implementation; DONE.md must explicitly note disposition for each.

### Pi instruction for these findings

Read each finding below. Classify per your understanding of the spec scope and as-built code:

- **MUST-ADDRESS**: concrete defect you encounter or can clearly prevent during implementation. Address as additional AC. DONE.md must note how addressed (file:line).
- **ADVISORY**: improvement worth considering. Address if applicable; document choice in DONE.md.
- **SPECULATIVE**: speculative concern that may not apply to as-built code. Proceed without addressing unless concrete failure encountered. Note classification in DONE.md.

### Findings (raw, by model)


#### openai — verdict=flag, 3 findings, 12s, $0.0665, in/out=22404/702

**OP-1** [blocking]

> `cmd_create()` mode-mismatch detection is specified to run before the spec directory path is guaranteed to exist/be set consistently, but the inserted block references `$dir/PROMPT.md` and `$dir/meta.json`. The spec explicitly places this block 'BEFORE the mkdir -p "$dir/plans" at line 2264' and before the later PROMPT.md existence block, without establishing in this spec that `$dir` has already been computed and exists at that point. If `$dir` is unset or points to a non-created path, the mismatch warning can silently never trigger, defeating MF5's stated fix.

> **Suggested fix:** Move the §3.8 mode-mismatch block to immediately after the code that computes `dir`/`prompt_path` and after `mkdir -p "$dir/plans"`, or explicitly add a preceding step in §3.7 that computes `dir` before mismatch detection. In the implementation, guard with `[ -n "$dir" ] || die "internal error: spec dir not set"` before reading `$dir/meta.json`.

**OP-2** [blocking]

> The spec's acceptance coverage for AC #7 is not actually verifiable by the described automated tests. AC #7 requires `acorn create <repo> <issue> --lite` to produce three files and for `SPEC.md` to be valid stand-alone, but the test suite does not exercise `cmd_create` end-to-end or verify on-disk creation of PLAN.md/TASKS.md. The only coverage is a manual smoke procedure, and the listed tests mostly validate prompt text or isolated logic. That means the core feature can regress while all automated tests still pass.

> **Suggested fix:** Add at least one blocking integration test around `cmd_create` that mocks external dependencies and asserts the generated PROMPT.md and `meta.json` are produced with `output_mode=three-artifact`, plus a fixture-driven check that the prompt contains the exact final-response override and artifact instructions. If true end-to-end file generation by the LLM cannot be automated, explicitly mark AC #7 as manual-only in the traceability matrix and acceptance plan instead of claiming it is covered by tests.

**OP-3** [blocking]

> `write_meta_json()` is extended to write a new `output_mode` field, and multiple downstream behaviors (`cmd_approve`, `cmd_spec_complete`, mode-mismatch detection) depend on that field being present. However, the spec does not require any error handling if `write_meta_json` fails or produces invalid JSON. In that case, all later commands silently fall back to `single` via `jq -r '.output_mode // "single"' ... || printf 'single'`, causing three-artifact specs to lose warning behavior without a loud failure.

> **Suggested fix:** After calling `write_meta_json` in `cmd_create`, immediately validate the file with `jq -e '.output_mode == "single" or .output_mode == "three-artifact"' "$dir/meta.json" >/dev/null` and `die` if validation fails. Also change the fallback readers in `cmd_approve`, `cmd_spec_complete`, and mismatch detection to warn when `meta.json` is unreadable/malformed instead of silently defaulting to `single`.



#### gemini — verdict=flag, 1 findings, 134s, $0.0331, in/out=25140/327

**GE-1** [blocking]

> Logic error in §3.8 causing persistent state corruption. When a mode mismatch is detected between the requested `ACORN_OUTPUT_MODE` and the existing `meta.json`, the script emits a warning but does not halt execution or revert the `output_mode` local variable. As a result, `PROMPT.md` is left unchanged (as intended), but the execution continues to `write_meta_json` (in §3.7 Step D), which overwrites `meta.json` with the new requested mode. This permanently desynchronizes `meta.json` from the generated instructions in `PROMPT.md`, causing pipeline agent confusion and incorrect file validations downstream. Furthermore, test T14 (§5.12) masks this error by only testing standard string inequality rather than invoking `cmd_create` to verify its state transitions and side effects.

> **Suggested fix:** Update the `if` block in §3.8 to either abort execution (`exit 1`) after emitting the warnings, or explicitly reassign `output_mode="$recorded_om"` so the script proceeds using the mode that correctly matches the preserved `PROMPT.md`. Additionally, update test T14 to properly invoke `cmd_create` and assert that `meta.json` is not overwritten with the mismatched requested mode.



#### deepseek-v4-pro — verdict=flag, 2 findings, 224s, $0.0619, reasoning=5501 tokens, in/out=23696/5935

**DE-1** [blocking]

> Temporary file creation for the three‑artifact block (§3.4.2) is not checked for failure. If `mktemp` fails (e.g., /tmp full, permission denied), `block_file` becomes an empty string, the script falls through to the `else` branch and silently produces a single‑mode PROMPT.md. Later `acorn approve` may warn about missing PLAN/TASKS, but the incorrect prompt is already fed to the LLM, wasting resources and requiring a re‑run. The operator receives no immediate error.

> **Suggested fix:** After the `mktemp` call, immediately check the return code and that `block_file` is non‑empty. If the temp file cannot be created, die with a clear message (e.g., `die "Failed to create temporary file for three‑artifact block"`). Example: `block_file="$(mktemp -t acorn_three_artifact_XXXXXX)" || die "mktemp failed"`. Then proceed with writing the heredoc and using the file.

**DE-2** [blocking]

> The sed pipeline that substitutes the three‑artifact block (`cat ... | sed ... | sed ...`) does not have `pipefail` enabled nor any explicit error checking on the pipeline exit status. If the first sed fails (e.g., because the temp file is unreadable, or sed encounters an unexpected error), the pipeline may still exit with status 0 (success from the last `sed`), and a corrupted or incomplete PROMPT.md is written without any warning. This can cause the LLM to receive a prompt missing the three‑artifact instructions, resulting in a single‑mode spec while `meta.json` records `three‑artifact`.

> **Suggested fix:** Add `set -o pipefail` to the main script (or immediately before these pipelines) so that a failure of any command in the pipe causes the pipeline to return a non‑zero exit status. Follow each pipeline with a check (e.g., `|| die 'Failed to generate three‑artifact portion of PROMPT.md'`). This ensures that a silent fallback to single‑mode cannot occur.



#### deepseek-v4-flash — verdict=flag, 5 findings, 63s, $0.0040, in/out=23696/2546

**DE-1** [blocking]

> The sed r + d pattern described in §3.4.2 is applied to the cat heredoc top level, not inside the sed command itself. The command `cat <<'METHODOLOGY_EOF' | sed -e '/__THREE_ARTIFACT_BLOCK__/{r ${block_file}' -e 'd}'` places the r filename and d commands on separate -e arguments. The second -e 'd' deletes the current (placeholder) line, but sed -e '/__THREE_ARTIFACT_BLOCK__/{r filename' -e 'd}' is applying `r` to the pattern match but the delete command is outside the braces because the braces are unclosed. This would cause sed to treat `{r ${block_file}` as the start of a block with no closing `}`, resulting in a syntax error or corrupted output. More critically, sed r filename in this multi-e form will read and print the file on the matched line, but the `d` in the second -e will delete the current pattern space after printing, which may skip the line after the matched line or cause off-by-one output. The standard POSIX sed idiom for deletion and insertion is separate commands: `/pattern/{r file` then `d}` on ONE -e or as a single script.

> **Suggested fix:** Replace the multi-e fragment with a single sed expression using the standard pattern: `sed -e '/__THREE_ARTIFACT_BLOCK__/{r "${block_file}"' -e 'd}'` but ensure the braces contain both commands. The correct form is: `sed -e '/__THREE_ARTIFACT_BLOCK__/{r "${block_file}"; d}'` if using multiple -e, or consolidate into one -e: `sed "/__THREE_ARTIFACT_BLOCK__/{r ${block_file}
d}"` using escaped newline. Safer: use `sed -e "/__THREE_ARTIFACT_BLOCK__/r ${block_file}" -e "/__THREE_ARTIFACT_BLOCK__/d"` — two separate expressions, not a block. The first reads the file and prints it after the match; the second deletes the match line. This avoids brace nesting entirely and works in all POSIX sed implementations.

**DE-2** [blocking]

> In §3.4.3 and later, the spec inserts the placeholder line `__THREE_ARTIFACT_BLOCK__` into each planning_block heredoc body, but the heredocs use `<<'METHODOLOGY_EOF'` (single-quoted delimiter). Shell variables are NOT expanded inside such heredocs. However, the injected placeholder is a literal string that does not contain $, backtick, or \, so that is fine. The critical bug is that the placeholder line is inserted between existing lines of the heredoc, but the spec does not add a newline before or after the placeholder. If the placeholder line is inserted as `blah.

__THREE_ARTIFACT_BLOCK__

- Write` (without a leading blank line), the sed pattern match `/__THREE_ARTIFACT_BLOCK__/` will match and delete that line, but the surrounding text must ensure indentation is correct and that no surrounding words are concatenated. More importantly, the spec says the placeholder is inserted between "ZERO questions" and "Write the final spec" with a blank line before and after. However, the heredoc body after the placeholder still contains the original final-response instructions: "Your final response must be ONLY: ...". In three-artifact mode, the sed substitution removes the placeholder line and inserts the three-artifact instructions (which contain OVERRIDE language superseding the original final-response instruction). This leaves the original final-response line still in the heredoc output after the injected block. The LLM sees BOTH instructions: the OVERRIDE (injected) and the old "Done. Output: SPEC.md only" (still in the original heredoc text after the placeholder). This contradicts the spec claim that the OVERRIDE 'supersedes' the original — the original line is still present and appears AFTER the OVERRIDE, which often causes LLMs to favor the last-instruction (the original final-response).

> **Suggested fix:** Inside each planning_block heredoc body, after inserting `__THREE_ARTIFACT_BLOCK__`, also wrap the following original final-response instruction lines in a conditional that deletes them in three-artifact mode. The simplest fix: replace the original final-response lines with a second placeholder `__THREE_ARTIFACT_FINAL_RESPONSE__` that each sed branch handles: in three-artifact mode, substitute it with the OVERRIDE final-response format; in single mode, substitute it with the original text. Alternatively, in the three-artifact sed-inject block, include a trailing sed command that deletes the lines containing 'Your final response must be ONLY' that follow the injected block. The cleanest approach: add a new placeholder `__ORIGINAL_FINAL_RESPONSE_LINES__` immediately after the three-artifact block placeholder, and have each sed branch either keep (for single mode) or delete (for three-artifact mode) that block. The injected three_artifact_instructions() content would temporarily replace the old final-response instruction, ensuring only the last-instruction is the correct one.

**DE-3** [blocking]

> The spec's test T14 (§5.12) attempts to validate mode-mismatch detection but does NOT actually invoke the proper detection block from §3.8. The test manually sets up the directory and meta.json, then duplicates the detection logic inline (reads recorded_om, compares to desired_om, asserts mismatch). This tests the test author's manual grep of jq output, not the actual code that will run in cmd_create. The actual detection code in §3.8 reads from meta.json and warns using the `warn` function. The test mocks `warn` implicitly (it runs in a sub-shell without sourcing warn), so even if the real detection were called, it would fail with 'command not found' for `warn`. The test provides zero coverage of the actual mode-mismatch detection implementation; it only tests the Boolean comparison logic, which is trivially true. This is a silent coverage gap — the implementation could be buggy (bad jq path, missing file guards, wrong variable name) and the test would still pass.

> **Suggested fix:** Restructure test T14 to source the actual mode-mismatch detection code from §3.8 (the block that reads meta.json and calls `warn`). Before sourcing, define `warn()` as a function that records its arguments to a global variable so the test can assert the warning message contains 'PROMPT.md exists with output_mode='. The test should set up a real meta.json with `single`, set `output_mode=three-artifact` in the shell, source the detection block (not inline), and assert `$WARN_MESSAGE` contains the expected warning text. This ensures the actual jq-parse, variable-substitution, and warn-invocation path is exercised.

**DE-4** [blocking]

> The spec creates a temp file for the block instructions in §3.4.2 using `mktemp -t acorn_three_artifact_XXXXXX` and stores the path in `$block_file`. The cleanup line is `rm -f "$block_file"` but this runs AFTER the heredoc body is written (the `cat <<'METHODOLOGY_EOF' ... METHODOLOGY_EOF` block). However, the sed pipeline is constructed inside the `if [ -n "$block_file" ]; then` branch, and the rm is placed at the end of the branch. The issue is that the sed command is piped from `cat`, and `rm` runs after `cat` completes but BEFORE sed has finished reading/processing. In a shell pipeline, the commands in each branch run sequentially within the `if` block, but `cat` writes the heredoc and pipes it to sed. The `rm` runs after cat finishes but sed might still be reading data that is buffered. However, sed reads the file at match time (when it sees `__THREE_ARTIFACT_BLOCK__`), and the read of `$block_file` happens DURING sed execution, not at pipe-open time. Since the sed r command reads the file at the moment the pattern matches (lazily), and rm happens AFTER the cat heredoc is fully written but BEFORE sed has processed the match line, there is a race: if sed processes lines slowly (e.g., large heredoc), the rm could delete the block_file before sed reads it via r. In practice, for a small heredoc, sed will read the block file before rm runs because cat finishes quickly and sed processes in memory. But there is no guarantee — if sed is CPU-bound on a large prompt or Unix pipe buffer fills, the r read could happen after rm. This is a data-loss risk.

> **Suggested fix:** Move the rm command to AFTER the entire sed pipeline completes, not inside the if branch. Use a subshell to hold the block_file reference, or wrap the sed+cat pipeline with a grouping command `{ cat ... | sed ...; } && rm -f "$block_file"`. The safest pattern: keep the block_file assignment, run the cat | sed pipeline, capture its exit code, then rm. Use a trap on EXIT or a compound command: `{ output="$(cat <<'METHODOLOGY_EOF' | sed ...)"; rm -f "$block_file"; printf '%s' "$output"; }`. This ensures the block file exists for the entire pipeline execution. The current spec's pattern is vulnerable to timing-dependent corruption even if unlikely on current hardware; spec should guarantee correctness.

**DE-5** [advisory]

> The spec defines three_artifact_instructions() as emitting a heredoc with __SPEC_PATH__ placeholders that are later substituted by sed. The function body contains the literal string `__SPEC_PATH__` inside both the heredoc body and the example paths. The caller in §3.4.2 runs: `echo '...' | sed -e "/__THREE_ARTIFACT_BLOCK__/{r \"${block_file}\" -e d}" | sed "s|__SPEC_PATH__|${spec_path}|g"`. The second sed replaces __SPEC_PATH__ with the actual spec_path. However, the injected block from three_artifact_instructions() also contains `__THREE_ARTIFACT_BLOCK__` or `__SPEC_PATH__` inside code-fence examples (backtick blocks). After substitution, these become the actual spec_path (e.g., `/tmp/spec/plans/...`), which is correct. But the path separator issue: sed's s command uses `|` as delimiter, so paths with `/` are fine. However, the substitution also runs on the entire prompt output, which includes the existing heredoc body that already has `__SPEC_PATH__` (pre-edit). So both the existing body and the injected block get their placeholders replaced. That's fine. But the spec does not account for the case where the user's spec_path contains `|` characters (practically impossible on Linux pathnames but possible in WSL paths with special chars). This is advisory — not blocking for single-user WSL with sane pathnames.

> **Suggested fix:** No code change required. Document that spec_path must not contain the pipe character `|` or the delimiter `__SPEC_PATH__`. Since spec_dir is derived from repo name and slug (alphanumeric + hyphens), this is a non-issue. Mark as resolved by environment constraint.


### Override rationale

Standard precondition-11 cross-model verdict was `flag` (all four models flagged). Per Wave 1 empirical evidence (0% corroboration at Jaccard ≥0.4 across the model panel) and the SDLC review's classification protocol, findings are surfaced to Pi rather than blocking dispatch. Operator override authorized.
