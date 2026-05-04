# Relevant Code Reconnaissance

## Summary

This feature adds three-artifact output (SPEC.md + PLAN.md + TASKS.md) to the Acorn pipeline. The entire implementation lives in a single file: `/home/agentdev/projects/acorn/main/bin/acorn` (3691 lines of bash). There are no separate modules, libraries, or helper files — all pipeline logic is in this monolithic bash script.

---

## Primary File: `/home/agentdev/projects/acorn/main/bin/acorn`

This is the only file that needs to be modified for this feature.

### Key Sections by Line Number

---

### 1. `planning_block()` — Mode Router (lines 662–671)

Routes to the correct planning block function based on mode. This is the central dispatch point for pipeline methodology generation.

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

**Relevance**: The three-artifact feature needs to inject PLAN.md and TASKS.md generation into the final spec-writing stage of each pipeline mode. The injection point is the Final Spec agent prompt inside each of: `planning_block_full()`, `planning_block_lite()`, and `planning_block_quick()`.

---

### 2. `planning_block_full()` — Full Pipeline (lines 673–1139)

Generates the full 6-stage pipeline PROMPT.md methodology block. The Final Spec agent prompt is at approximately lines 1074–1122:

```bash
planning_block_full() {
  local spec_path="${1:-.}"
  cat <<'METHODOLOGY_EOF' | sed "s|__SPEC_PATH__|${spec_path}|g"
  ...
  ### Stage 5: Final Spec with Traceability
  ...
  - Write the final spec to __SPEC_PATH__/plans/SPEC.md
  - Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
  - Your final response must be ONLY: "Done. Output: __SPEC_PATH__/plans/SPEC.md"
```

**Relevance**: In three-artifact mode, the Final Spec (Stage 5) agent needs an additional instruction to also emit `__SPEC_PATH__/plans/PLAN.md` and `__SPEC_PATH__/plans/TASKS.md`.

---

### 3. `planning_block_lite()` — Lite Pipeline (lines 1141–1417)

Generates the lite 4-stage pipeline PROMPT.md methodology block. The Final Spec agent prompt is at approximately lines 1350–1399:

```bash
planning_block_lite() {
  local spec_path="${1:-.}"
  cat <<'METHODOLOGY_EOF' | sed "s|__SPEC_PATH__|${spec_path}|g"
  ...
  ### Stage 3: Final Spec
  ...
  - Write the final spec to __SPEC_PATH__/plans/SPEC.md
  - Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
  - Your final response must be ONLY: "Done. Output: __SPEC_PATH__/plans/SPEC.md"
```

**Relevance**: Same injection point as full mode — Stage 3 Final Spec agent needs expanded instructions for three-artifact mode.

---

### 4. `planning_block_quick()` — Quick Pipeline (lines 1419–1607)

Generates the quick 2-stage pipeline PROMPT.md methodology block. The Direct Spec agent prompt is at approximately lines 1540–1590:

```bash
planning_block_quick() {
  local spec_path="${1:-.}"
  cat <<'METHODOLOGY_EOF' | sed "s|__SPEC_PATH__|${spec_path}|g"
  ...
  ### Stage 1: Direct Spec
  ...
  - Write the final spec to __SPEC_PATH__/plans/SPEC.md
  - Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
  - Your final response must be ONLY: "Done. Output: __SPEC_PATH__/plans/SPEC.md"
```

**Relevance**: Quick mode Stage 1 Direct Spec agent needs the same expansion.

---

### 5. `planning_block()` Call in `render_prompt_md()` (lines 1621–1669)

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
  ...
}
```

**Relevance**: `render_prompt_md` is the function that assembles the PROMPT.md file written to disk. It already takes `mode` and `spec_path` as parameters, so adding `output_mode` (the new `ACORN_OUTPUT_MODE` env var) can be threaded through here.

---

### 6. `cmd_create()` — Main Create Command (lines 2209–2350)

This function handles `acorn create <repo> <issue-number>`. It:
1. Parses `--lite` / `--quick` flags (lines 2213–2234)
2. Calls `render_prompt_md` to write PROMPT.md (line 2276)
3. Creates spec directory structure with `mkdir -p "$dir/plans"` and `mkdir -p "$dir/recon"` (lines 2264–2266)

```bash
cmd_create() {
  local repo="$1"
  local issue_number="$2"
  shift 2

  local auto_trigger=1
  local mode="full"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --no-auto)  auto_trigger=0 ;;
      --lite)     [ "$mode" = "full" ] || die "--lite and --quick are mutually exclusive"; mode="lite" ;;
      --quick)    [ "$mode" = "full" ] || die "--lite and --quick are mutually exclusive"; mode="quick" ;;
      *)          die "Unknown option for create: $1" ;;
    esac
    shift
  done
  ...
  mkdir -p "$dir/plans"
  mkdir -p "$dir/recon"
  mkdir -p "$dir/images"
  ...
  render_prompt_md "$title" "$body" "$issue_json" "$tmp_path" "$mode" "$dir" "$url_mapping_file"
```

**Relevance**: The `ACORN_OUTPUT_MODE` env var will be read here (or in `render_prompt_md`), and the mode selection passed through to `planning_block()`.

---

### 7. `cmd_approve()` — Approve Command (lines 2392–2432)

```bash
cmd_approve() {
  local repo="$1"
  local slug="$2"

  require_cmds gh jq
  local repo_main
  repo_main="$(safe_repo_main "$repo")"
  local dir
  dir="$(spec_dir "$repo" "$slug")"

  [ -d "$dir" ] || die "Spec directory missing: $dir"
  [ -f "$dir/plans/SPEC.md" ] || die "Missing final plan: $dir/plans/SPEC.md"
  ...
}
```

**Relevance**: Acceptance Criteria #6 requires `acorn approve` to warn (not error) if PLAN.md or TASKS.md are missing when `ACORN_OUTPUT_MODE=three-artifact`. The guard `[ -f "$dir/plans/SPEC.md" ] || die ...` should remain; new warnings for PLAN.md and TASKS.md should be added after it.

---

### 8. `cmd_spec_complete()` — Spec Complete Command (lines 2434–2469)

```bash
cmd_spec_complete() {
  local repo="$1"
  local slug="$2"

  require_cmds gh jq
  local repo_main
  repo_main="$(safe_repo_main "$repo")"
  local dir
  dir="$(spec_dir "$repo" "$slug")"

  [ -d "$dir" ] || die "Spec directory missing: $dir"
  [ -f "$dir/plans/SPEC.md" ] || die "Missing final plan: $dir/plans/SPEC.md"
  ...
}
```

**Relevance**: Same as `cmd_approve` — needs the same optional warnings for PLAN.md/TASKS.md in three-artifact mode.

---

### 9. `write_meta_json()` — Metadata Writer (lines 1948–1971)

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
    '{repo:$repo, issue_number:$issue_number, issue_title:$issue_title, slug:$slug, created_at:$created_at, session_backend:$session_backend, session_name:$session_name, mode:$mode}' \
    > "$path"
}
```

**Relevance**: `meta.json` stores the pipeline `mode` (full/lite/quick). It could optionally also store `output_mode` (single/three-artifact), which would allow `cmd_approve` and `cmd_spec_complete` to detect three-artifact mode from spec metadata without requiring the env var to be set at approve-time. This is a design decision point.

---

### 10. `auto_trigger_message()` — Auto-trigger Text (lines 25–33)

```bash
auto_trigger_message() {
  local spec_path="$1"
  local mode="${2:-full}"
  case "$mode" in
    full)  printf 'Read %s/PROMPT.md and follow ALL instructions in it to execute the full 6-stage planning pipeline. Start with Stage 0 (Recon). Write all output files to %s/' "$spec_path" "$spec_path" ;;
    lite)  printf 'Read %s/PROMPT.md and follow ALL instructions in it to execute the lite 4-stage planning pipeline. Start with Stage 0 (Recon). Write all output files to %s/' "$spec_path" "$spec_path" ;;
    quick) printf 'Read %s/PROMPT.md and follow ALL instructions in it to execute the quick 2-stage planning pipeline. Start with Stage 0 (Recon). Write all output files to %s/' "$spec_path" "$spec_path" ;;
  esac
}
```

**Relevance**: This message is sent to the Claude session. It may need no change since the PROMPT.md already encodes the mode behavior, but it's the trigger for the pipeline. No changes required unless additional context is needed.

---

## Pi Model Recommendation Block in Final Spec Prompts

The final spec agent prompt in all three pipeline modes already includes the `## Pi Model Recommendation` section instruction (lines ~1105–1114 in full, ~1383–1392 in lite, ~1573–1581 in quick):

```
6. **Pi Model Recommendation**: Based on the full context of this spec, emit a `## Pi Model Recommendation`
   section at the top of SPEC.md (before ## 1. Requirements Traceability Matrix) containing exactly two lines:

   suggested_pi_model: codex
   suggested_pi_model_rationale: <one-line explanation>
```

This instruction is already present in all three mode blocks. The three-artifact expansion needs to fit alongside this instruction.

---

## Existing Spec Directory Structure

From the `acorn.md` documentation (lines 211–223) and codebase, the current spec output layout is:

```
.specs/<slug>/
  PROMPT.md              # Generated requirements + planning methodology
  meta.json              # Metadata (repo, issue, session info, mode)
  images/
  recon/
    architecture.md
    relevant_code.md
    conventions.md
  plans/
    draft_plan_1..4.md    (full only)
    draft.md              (lite only)
    evaluation.md         (full only)
    master_plan.md        (full only)
    validation.md         (lite only)
    red_team_1..4.md      (full only)
    SPEC.md               (all modes)
```

Three-artifact mode adds to `plans/`:
```
    PLAN.md               (new, three-artifact mode only)
    TASKS.md              (new, three-artifact mode only)
```

---

## Environment Variable: `ACORN_OUTPUT_MODE`

Currently, no `ACORN_OUTPUT_MODE` variable exists in the codebase. The feature requires adding it. The relevant read points will be:

1. In `cmd_create()` (or `render_prompt_md()`) to select the appropriate planning block variant
2. In `cmd_approve()` to conditionally warn about missing PLAN.md/TASKS.md
3. In `cmd_spec_complete()` for the same warning

The default value is `single` (backwards-compatible). Forge consumers set `ACORN_OUTPUT_MODE=three-artifact`.

---

## Test Infrastructure

Tests source the acorn script with main() stripped:

```bash
# From test/test_split.sh, line 8:
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"
```

This pattern (used across all test files) means any new bash functions added to `bin/acorn` are automatically testable by sourcing the script. New tests for three-artifact mode should follow this pattern.

Test files use:
- `assert_eq`, `assert_contains`, `assert_not_contains` helper functions
- Mock functions via `export -f` to override gh, claude, etc.
- `mktemp -d` for temporary spec directories

**Test file naming**: `test/test_<feature>.sh` — new tests should go in `test/test_three_artifact.sh` or similar.

---

## Relevant Existing Test: `test/test_labels.sh`

The test at line 134 (`test_status_for_spec_reads_lifecycle_label`) shows how spec file existence is tested:

```bash
touch "$tmpdir/plans/SPEC.md"
result="$(status_for_spec "$tmpdir" "1" "$tmpdir")"
assert_eq "fallback review" "$result" "review"
```

This confirms the test pattern for checking `plans/SPEC.md` existence, which mirrors what `cmd_approve` and `cmd_spec_complete` do.

---

## Claude Commands Documentation

`/home/agentdev/projects/acorn/main/claude/commands/acorn.md` — the user-facing reference. It documents the project layout table (lines 211–223) and will need updating to show PLAN.md and TASKS.md in the three-artifact output column.

---

## Feature Injection Points Summary

| Location | What Changes | AC Reference |
|---|---|---|
| `planning_block_full()` ~line 1074 | Expand Stage 5 Final Spec prompt to emit PLAN.md + TASKS.md | AC #2, #3, #4, #5 |
| `planning_block_lite()` ~line 1350 | Expand Stage 3 Final Spec prompt to emit PLAN.md + TASKS.md | AC #2, #3, #4, #5 |
| `planning_block_quick()` ~line 1540 | Expand Stage 1 Direct Spec prompt to emit PLAN.md + TASKS.md | AC #2, #3, #4, #5 |
| `render_prompt_md()` line 1621 | Read `ACORN_OUTPUT_MODE` and pass to `planning_block()` | AC #1 |
| `planning_block()` line 662 | Pass `output_mode` to each planning_block_* function | AC #1 |
| `cmd_approve()` line 2392 | Add warn for missing PLAN.md/TASKS.md in three-artifact mode | AC #6 |
| `cmd_spec_complete()` line 2434 | Add warn for missing PLAN.md/TASKS.md in three-artifact mode | AC #6 |
| `write_meta_json()` line 1948 | Optionally record output_mode in meta.json | AC #1 (optional) |
| `claude/commands/acorn.md` | Update docs to describe PLAN.md and TASKS.md | AC #7 |

---

## PLAN.md and TASKS.md Schema Encoding

The feature requires the Final Spec agent to receive a prompt that specifies the schemas for the new artifacts. The schemas (from PROMPT.md Acceptance Criteria #3 and #4) need to be embedded verbatim in the agent prompts inside each `planning_block_*()` heredoc.

**PLAN.md required sections** (AC #3):
1. Architecture decisions with rationale (1-3 bullet points; cite alternatives considered)
2. API contracts (inputs / outputs / side effects per touched function or interface)
3. Data model changes (schemas, migrations, atomic-rename patterns)
4. Implementation sequence (phase names + dependencies)
5. Risk register (known unknowns)

**TASKS.md YAML schema** (AC #4):
```yaml
- id: T1
  title: "Add verified_send helper to forged.py"
  size: M  # XS/S/M/L/XL
  files: [runtime/foreman/bin/forged.py]
  verify: "pytest -q runtime/foreman/test/test_forged.py::test_verified_send"
  depends_on: []
```
XL tasks (>8 files OR >3 new interfaces) flagged with `⚠️ XL: requires decomposition` note.

**SPEC.md backwards-compat in three-artifact mode** (AC #5):
- Trim §3 Implementation Plan substance (moves to PLAN.md)
- Trim §7 Acceptance Criteria substance (moves to TASKS.md)
- SPEC.md remains valid stand-alone (functional requirements, traceability matrix, risk register pointer)

---

## No New Dependencies Required

The feature is pure prompt and output-parser changes. The bash script already uses:
- `jq` — for JSON parsing (already required)
- `mkdir -p` — for directory creation (already used)
- No new external tools needed (AC #8 satisfied)

The Final Spec agents already write files using the Write/Edit tool pattern. PLAN.md and TASKS.md are written by the same agent, same pattern, same tool calls.
