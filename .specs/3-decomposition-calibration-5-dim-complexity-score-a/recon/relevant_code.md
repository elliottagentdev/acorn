# Relevant Code Reconnaissance

## Primary File to Modify

### `/home/agentdev/projects/elliottagentdev/acorn/bin/acorn` (4227 lines, single Bash script)

This is the only executable. All logic lives here. Tests source it via:
```bash
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"
```
This strips the `main "$@"` invocation and imports all function definitions into the test shell.

---

## Key Functions for This Feature

### 1. `analyze_issue_for_split()` — Lines 3208–3295

The primary target for extension. Currently returns a 3-key JSON:
```json
{
  "should_split": true/false,
  "reasoning": "...",
  "sub_issues": [{"title": "...", "scope": "..."}]
}
```

**Signature (line 3208):**
```bash
analyze_issue_for_split() {
  local issue_title="$1"
  local issue_body="$2"
  local issue_comments="${3:-}"
  local model="${4:-claude-sonnet-4-5}"
```

**Current Claude prompt structure (lines 3215–3242):** Qualitative only. Uses `claude -p --model "$model"` one-shot headless. Parses JSON from stdout, handles raw JSON and markdown-fenced JSON.

**JSON validation (line 3291):**
```bash
printf '%s' "$json" | jq -e 'has("should_split") and has("reasoning") and has("sub_issues")' >/dev/null 2>&1
```
This is the contract guard. Any extension must use `has()` form (avoids short-circuit on false values) and must NOT break this existing check.

**Called from (line 3556):**
```bash
analysis="$(analyze_issue_for_split "$title" "$body" "$comments_rendered" "$model")"
```
In `cmd_issue_split()`.

---

### 2. `cmd_issue_split()` — Lines 3503–3605

The existing manual split command. Calls `analyze_issue_for_split()`, checks `should_split`, validates `sub_issues` count >= 2.

**Key checks to preserve (lines 3563–3578):**
```bash
should_split="$(printf '%s' "$analysis" | jq -r '.should_split')"
if [ "$should_split" != "true" ]; then
  echo "No split recommended. Proceed with the original issue."
  echo "Next: acorn create $repo $issue_number"
  return 0
fi

sub_count="$(printf '%s' "$analysis" | jq '.sub_issues | length')"
if [ "$sub_count" -lt 2 ]; then
  warn "AI recommended split but provided fewer than 2 sub-issues ($sub_count). Treating as no-split."
  ...
fi
```

**The feature requires:** When complexity band is HIGH (score ≥ 12), `cmd_issue_split` must ALSO surface the decomposition proposal (or it can be handled inside `analyze_issue_for_split` extended output).

---

### 3. `render_prompt_md()` — Lines 1803–1883

**Signature:**
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

Called from `cmd_create()` at line 2524:
```bash
render_prompt_md "$title" "$body" "$issue_json" "$tmp_path" "$mode" "$dir" "$url_mapping_file" "$output_mode"
```

This function writes PROMPT.md. It calls `planning_block "$mode" "$spec_path"` (line 1835) which injects the planning methodology instructions for the Claude session that will run the spec pipeline.

**Key insertion point:** The feature needs to inject complexity-scoring instructions into the planning block so that the final-spec agent computes and records the 5-dim score in SPEC.md. Alternatively, `render_prompt_md` can invoke `analyze_issue_for_split` to compute a preliminary score from the issue body and embed it in PROMPT.md.

---

### 4. `planning_block()` and variants — Lines 760–1578

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

Three variants: `planning_block_full()` (line 771), `planning_block_lite()` (line 1275), `planning_block_quick()` (line 1581). Each uses a `cat <<'METHODOLOGY_EOF'` heredoc with sed substitutions for `__SPEC_PATH__`, `__RETRY_BUDGET__`, `__RETRY_BACKOFF__`, `__EVENT_PATH_DISPLAY__`, `__MODE__`.

**The final-spec agent prompt** in all three modes includes a "Pi Model Recommendation" section instructing the agent to emit it in SPEC.md. The complexity score section should be structured similarly — as instructions to the final-spec agent to compute and record it.

**Full mode final-spec prompt (lines 1195–1252):**
Includes 5 required sections: Requirements Traceability Matrix, Validation Resolution Log, Implementation Plan, Testing Strategy, Risk Register, plus Pi Model Recommendation.

**Lite mode final-spec prompt (lines 1504–1558):** Same 5+1 structure.

**Quick mode final-spec prompt (lines 1720–1771):** Same structure.

---

### 5. `cmd_create()` — Lines 2448–2612

The primary spec-authoring path triggered by `acorn create <repo> <issue#>` and by `cmd_issue_plan`. Key flow:
1. Fetches issue JSON from GitHub
2. Builds slug, creates spec directories (`$dir/plans`, `$dir/recon`, `$dir/images`)
3. Calls `render_prompt_md()` → writes PROMPT.md
4. Creates/starts tmux session with Claude Code
5. Sends auto-trigger message

**Mode flags (lines 2455–2470):**
```bash
local mode="full"
--lite  → mode="lite"
--quick → mode="quick"
```

**ACORN_OUTPUT_MODE env var (line 2503):**
```bash
local output_mode="${ACORN_OUTPUT_MODE:-single}"
```

---

### 6. `cmd_issue_plan()` — Lines 3757–3830

Chains `create_issue_in_repo` + `cmd_create`. This is `acorn issue plan`. The complexity scoring must appear automatically here too (it flows through `cmd_create`).

---

### 7. `format_split_recommendation()` — Lines 3299–3331

Currently displays split analysis as human-readable text. If complexity score is added to the JSON, this function needs to optionally render it.

```bash
format_split_recommendation() {
  local json="$1"
  local parent_issue_number="$2"

  local should_split reasoning
  should_split="$(printf '%s' "$json" | jq -r '.should_split')"
  reasoning="$(printf '%s' "$json" | jq -r '.reasoning')"
  ...
}
```

---

### 8. Global Config Variables — Lines 5–16

```bash
ACORN_SUBAGENT_RETRY_BUDGET="${ACORN_SUBAGENT_RETRY_BUDGET:-1}"
ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS="${ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS:-30}"
ACORN_FAILURE_EVENT_PATH="${ACORN_FAILURE_EVENT_PATH:-}"
ACORN_OUTPUT_MODE="${ACORN_OUTPUT_MODE:-single}"
```

**New env vars needed (per config-over-hardcoding requirement):**
```bash
ACORN_COMPLEXITY_LOW_MAX="${ACORN_COMPLEXITY_LOW_MAX:-7}"      # sum ≤7 = LOW
ACORN_COMPLEXITY_MED_MAX="${ACORN_COMPLEXITY_MED_MAX:-11}"     # sum 8-11 = MED
# HIGH = sum ≥12 (implicit: > MED_MAX)
ACORN_COMPLEXITY_LOC_THRESHOLD="${ACORN_COMPLEXITY_LOC_THRESHOLD:-800}"
ACORN_COMPLEXITY_FILES_THRESHOLD="${ACORN_COMPLEXITY_FILES_THRESHOLD:-8}"
```

---

## Existing JSON Contract (Must Not Break)

`analyze_issue_for_split()` currently produces and validates:
```json
{
  "should_split": true,
  "reasoning": "...",
  "sub_issues": [
    {"title": "...", "scope": "..."}
  ]
}
```

Consumers checking this contract:
- **Line 3291**: `jq -e 'has("should_split") and has("reasoning") and has("sub_issues")'`
- **Line 3563**: `jq -r '.should_split'`
- **Line 3574**: `jq '.sub_issues | length'`
- **`test/test_split.sh`**: All existing tests mock `analyze_issue_for_split` and parse these fields

**Extension strategy:** Add new fields to the JSON without removing existing ones:
```json
{
  "should_split": true,
  "reasoning": "...",
  "sub_issues": [...],
  "complexity_score": 13,
  "complexity_band": "HIGH",
  "complexity_breakdown": {
    "files_touched": 3,
    "LOC_estimate": 2,
    "novelty": 3,
    "context_depth": 3,
    "cross_module_fan_out": 2
  },
  "size_flag": {
    "loc_exceeds_threshold": false,
    "files_exceeds_threshold": false,
    "decomposition_review_required": false
  },
  "atomic_justification": null
}
```

---

## Spec-Authoring Integration Point

The complexity score needs to be recorded in the SPEC header. Two approaches:

**Approach A (shell-computed at PROMPT.md time):** Call `analyze_issue_for_split` from `render_prompt_md` / `cmd_create` using the issue title+body, embed the preliminary score in PROMPT.md as metadata. This runs early (before recon) using only the issue text.

**Approach B (agent-computed at SPEC.md time):** Inject instructions into all three `planning_block_*` final-spec agent prompts to have the Final Spec agent compute and record the 5-dim score in the SPEC header. This runs late (after recon+plan) using full context.

**Approach C (hybrid):** Shell computes preliminary score from issue body at `cmd_create` time; embed it in PROMPT.md header. Final-spec agent refines it using recon+plan artifacts and records the final score in SPEC.md.

The PROMPT.md currently starts with:
```
# Feature Spec: <title>
## Requirements
...
## Discussion / Context
...
---
[planning_block]
```

Embedding a complexity estimate block between `## Requirements` section and the `---` separator is the minimal-surgery approach.

---

## stage_manifest() — Lines 125–147

Defines what artifacts are expected per stage/mode. The SPEC.md is expected at:
- `full:5`, `lite:3`, `quick:1` → `plans/SPEC.md|^## `

This means `validate_stage_artifacts` checks that SPEC.md exists and has a `## ` heading. Any new complexity score heading in SPEC.md must NOT conflict with this validation.

---

## `write_meta_json()` — Lines 2180–2205

Writes `meta.json` with fixed keys. If complexity score is stored in meta.json, this function must be extended:
```bash
write_meta_json() {
  local path="$1" repo="$2" issue_number="$3" issue_title="$4" slug="$5"
  local backend="$6" session_name="$7" mode="${8:-full}" output_mode="${9:-single}"
  ...
  jq -n \
    ... \
    '{repo:$repo, issue_number:$issue_number, ...mode:$mode, output_mode:$output_mode}'
}
```

Currently does not store complexity score. The complexity score could be stored either in `meta.json` (if computed at create-time) or left only in SPEC.md (if computed by the final-spec agent).

---

## Existing Test Infrastructure

### `test/test_split.sh` — Primary target for extension

**Pattern:** Sources `bin/acorn` via eval (stripping main invocation). Mocks external calls (gh, claude, etc.) via Bash function overrides. Each test group calls `setup`/`teardown`. Uses `assert_eq`, `assert_contains`, `assert_not_contains`.

**Key mock pattern:**
```bash
claude() {
  cat <<'MOCK_EOF'
{"should_split":true,"reasoning":"test reason","sub_issues":[...]}
MOCK_EOF
}
export -f claude

result="$(analyze_issue_for_split "Test title" "Test body" "" "mock" 2>/dev/null)"
```

**Key teardown:**
```bash
unset -f analyze_issue_for_split  # Can override the function itself
```

**Existing tests in test_split.sh:**
- `test_format_recommendation_split` — verifies split=true display
- `test_format_recommendation_no_split` — verifies split=false display
- `test_analyze_raw_json` — verifies raw JSON parsing
- `test_analyze_fenced_json` — verifies fenced JSON parsing
- `test_analyze_invalid_json` — verifies die on bad JSON
- `test_cmd_split_no_split` — verifies no-split flow
- `test_cmd_split_too_few_sub_issues` — verifies < 2 sub-issues guard
- `test_cmd_split_unknown_flag` — verifies unknown flag error
- `test_create_sub_issues` — verifies sub-issue creation

**These must all still pass after the extension.** The mock `claude()` in existing tests returns JSON without the new fields — so the code must handle missing complexity fields gracefully (backward compat).

**New test file location:** `test/test_complexity_score.sh` — following the same pattern as `test_split.sh`. Must include:
- Negative control that FAILS on live-base (prove-it-first)
- Test: HIGH-scored fixture triggers decomposition proposal
- Test: LOW/MED fixture does NOT trigger decomposition proposal
- Test: 800-LOC threshold fires
- Test: >8-file threshold fires
- Test: existing `analyze_issue_for_split` JSON contract unchanged (backward compat)

### `test/test_recon_completeness.sh`

Tests `validate_stage_artifacts`, `halt_pipeline_diagnostic`, `status_for_spec`, `validate_prompt_md`.

**`validate_prompt_md()` (line 1886):**
```bash
validate_prompt_md() {
  local prompt_path="$1"
  local output_mode="${2:-single}"
  grep -q 'PLANNING METHODOLOGY — MANDATORY INSTRUCTIONS' "$prompt_path" || return 1
  if [ "$output_mode" = "three-artifact" ]; then
    grep -q 'THREE-ARTIFACT OUTPUT MODE' "$prompt_path" || return 1
  fi
  if grep -E -q '__SPEC_PATH__|__RETRY_BUDGET__|__RETRY_BACKOFF__|__EVENT_PATH_DISPLAY__|__MODE__' "$prompt_path"; then
    return 1
  fi
  return 0
}
```

If new placeholder tokens are added to planning blocks, they must be added to this sentinel check.

### `test/test_three_artifact.sh`

Tests `render_prompt_md` with `three-artifact` mode. Mocks multiple functions. Pattern to follow for new complexity-score tests of `render_prompt_md`.

### `test/test_auto_trigger_clarify_hint.sh` and `test/test_planning_block_clarify.sh`

These two test files reference `planning_block_clarify` and `ACORN_CLARIFY_ENABLED` — functions/vars that do NOT exist in the live-base `bin/acorn`. These are pre-existing failing tests from the backedout clarify feature. They are out of scope (PROMPT.md explicitly says "DO NOT touch the pre-Stage-0 /clarify code").

---

## Summary: Implementation Surface

**Files to modify:**
- `bin/acorn` (primary — the only runtime file)
- `test/test_split.sh` (verify backward compat tests still pass)

**Files to create:**
- `test/test_complexity_score.sh` (new complexity score tests with negative controls)

**Key functions to modify or add in `bin/acorn`:**
1. Add `compute_complexity_score()` — new function that calls `claude -p` with a scoring prompt; returns extended JSON with `complexity_score`, `complexity_band`, `complexity_breakdown`, `size_flag`, `atomic_justification`
2. Modify `analyze_issue_for_split()` — extend its prompt and JSON output to include the 5-dim score; preserve existing 3-key contract
3. Modify `planning_block_full()`, `planning_block_lite()`, `planning_block_quick()` — add instructions to the final-spec agent prompt to compute and embed the complexity score in SPEC.md header
4. Add new env var defaults at top of file: `ACORN_COMPLEXITY_LOW_MAX`, `ACORN_COMPLEXITY_MED_MAX`, `ACORN_COMPLEXITY_LOC_THRESHOLD`, `ACORN_COMPLEXITY_FILES_THRESHOLD`
5. Optionally modify `format_split_recommendation()` to display complexity score when present

**NOT in scope:**
- `planning_block_clarify` or `ACORN_CLARIFY_ENABLED` (backedout clarify feature)
- Deployment to `~/acorn/bin` or `~/.foreman/bin`
- Any other command paths beyond `analyze_issue_for_split`, `cmd_issue_split`, and the planning_block functions

---
