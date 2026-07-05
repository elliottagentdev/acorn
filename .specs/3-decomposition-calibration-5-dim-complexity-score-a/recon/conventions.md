## Conventions & Constraints: Acorn Codebase

### Project Layout

```
acorn/
├── bin/acorn          # Single-file bash script (4,227 lines), the entire codebase
├── test/              # Shell test files (test_*.sh), each tests a subset of bin/acorn functions
│   ├── test_split.sh
│   ├── test_auto_trigger.sh
│   ├── test_recon_completeness.sh
│   ├── test_three_artifact.sh
│   ├── test_labels.sh
│   ├── test_approve_commit.sh
│   ├── test_planning_block_clarify.sh
│   ├── test_rt_gate_removal.sh
│   ├── test_idle_detect.sh
│   ├── test_idle_e2e.sh
│   ├── test_auth_preflight.sh
│   ├── test_concurrent_launch.sh
│   ├── test_doctor.sh
│   ├── test_dependencies.sh
│   ├── test_images.sh
│   ├── test_notify.sh
│   └── test_path_npm_global.sh
├── .claude/skills/    # Claude skill definitions
├── evals/             # Evaluation sets
├── claude/            # Claude command definitions
└── README.md
```

The entire implementation is a single bash script (`bin/acorn`). There is no build step, no compilation, no separate library files.

---

## Coding Style and Naming Conventions

### Bash Header (Mandatory)

Every script (including bin/acorn) begins:

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
```

Test files use the same trio. Some tests drop `IFS` but use the same `set -euo pipefail`.

### Variable Naming

- **Global config env vars**: `SCREAMING_SNAKE_CASE` with `ACORN_` prefix for acorn-specific vars, or well-known names (`PROJECTS_DIR`, `FOREMAN_HOME`, `TELEGRAM_NOTIFY_PORT`).
- **Internal global flags**: underscore-prefixed (`_SHOW_DEPS`, `_LIST_NWO`).
- **Local variables**: `snake_case`, always declared with `local`.
- **Arrays**: `snake_case` with parentheses (`LIFECYCLE_LABELS=(...)` is a global array in SCREAMING_SNAKE_CASE).

### Function Naming

- **Public commands** (called via main dispatch): `cmd_<verb>` or `cmd_<noun>_<verb>` — e.g., `cmd_create`, `cmd_issue_split`, `cmd_issue_plan`.
- **Internal helpers**: descriptive `snake_case` — e.g., `analyze_issue_for_split`, `format_split_recommendation`, `validate_stage_artifacts`, `planning_block_lite`.
- **Setup/teardown utilities**: `ensure_labels`, `require_cmds`, `safe_repo_main`, `spec_root`, `spec_dir`.
- **Notification helpers**: `notify_telegram`, `notify_foreman`.

### Output / Printing Conventions

```bash
info()  { printf '[INFO] %s\n' "$*"; }        # stdout, informational
warn()  { printf '[WARN] %s\n' "$*" >&2; }    # stderr, non-fatal
die()   { printf '[ERROR] %s\n' "$*" >&2; exit 1; }  # stderr, fatal
```

Use `printf` (not `echo`) everywhere for portability. `printf '%s\n'` is the standard pattern.
`echo ""` and `echo "string"` are occasionally used for human-readable output sections (e.g. `format_split_recommendation`), but `printf` is preferred in library functions.

### String Quoting and Piping

- Always `printf '%s' "$var"` before piping to jq, grep, sed — avoids subshell/newline hazards vs `echo "$var"`.
- JSON values extracted via: `printf '%s' "$json" | jq -r '.field // "default"'`

---

## Error Handling Patterns

### die() is the canonical fatal-exit

```bash
die "Missing required command(s): ${missing[*]}"
die "Unknown option for create: $1"
die "Failed to fetch issue #$issue_number"
```

### Guards with || die

```bash
issue_json="$(gh_issue_json "$repo_main" "$issue_number")" \
  || die "Failed to fetch issue #$issue_number"
```

### Subshell error capture

When calling external tools that may fail and you need stderr:

```bash
local stderr_file
stderr_file="$(mktemp)" || die "Failed to create temp file for stderr capture"
local response
response="$(printf '%s' "$full_prompt" | claude -p --model "$model" 2>"$stderr_file")" || {
  local err_msg=""
  [ -f "$stderr_file" ] && err_msg="$(<"$stderr_file")"
  rm -f "$stderr_file"
  die "Failed to get split analysis from Claude. Error: ${err_msg:-unknown}. Is the claude CLI installed and authenticated?"
}
rm -f "$stderr_file"
```

### Graceful-degradation (|| true)

For non-critical operations (notifications, label management, event logging):

```bash
gh label create "$label" ... >/dev/null 2>&1 || true
notify_telegram "..." 2>/dev/null || true
printf '%s\n' "$payload" >> "$event_path" 2>/dev/null || true
```

### JSON validation before use

Always validate JSON structure with `jq -e` before trusting field values:

```bash
printf '%s' "$json" | jq -e 'has("should_split") and has("reasoning") and has("sub_issues")' >/dev/null 2>&1 \
  || die "Split analysis returned invalid JSON structure. Got: $json"
```

Use `jq -e 'type == "array"'` for array checks before iterating.

### Integer guard pattern

For env vars that must be integers:

```bash
case "$retry_budget" in ''|*[!0-9]*) retry_budget=1 ;; esac
case "$retry_backoff" in ''|*[!0-9]*) retry_backoff=30 ;; esac
```

### set +e / set -e around expected-failure calls

When checking exit codes manually:

```bash
set +e
local err; err="$(validate_stage_artifacts "$sd" lite 0 2>&1)"; local rc=$?
set -e
```

---

## Config / Env-Var Patterns (Config-Over-Hardcoding)

### Pattern: top-level env resolution with default

All configurable values are resolved at the top of `bin/acorn` using `${VAR:-default}`:

```bash
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"
TELEGRAM_NOTIFY_PORT="${TELEGRAM_NOTIFY_PORT:-8765}"
TELEGRAM_NOTIFY_URL="http://127.0.0.1:${TELEGRAM_NOTIFY_PORT}/notify"
ACORN_SUBAGENT_RETRY_BUDGET="${ACORN_SUBAGENT_RETRY_BUDGET:-1}"
ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS="${ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS:-30}"
ACORN_FAILURE_EVENT_PATH="${ACORN_FAILURE_EVENT_PATH:-}"
ACORN_OUTPUT_MODE="${ACORN_OUTPUT_MODE:-single}"
```

### Pattern: inline env resolution at point of use

For optional Forge integrations resolved at call site:

```bash
local foreman_home="${FOREMAN_HOME:-$HOME/.foreman}"
local auth_check="${FOREMAN_HOME:-$HOME/.foreman}/bin/auth-check.sh"
local watchdog_state="${FOREMAN_HOME:-$HOME/.foreman}/watchdog-state"
```

### Pattern: env vars propagated into planning blocks via sed substitution

In `planning_block_lite()`, `planning_block_full()`, `planning_block_quick()`, config values are injected into heredoc strings using sed substitution of `__PLACEHOLDER__` tokens:

```bash
planning_block_lite() {
  local spec_path="${1:-.}"
  local retry_budget="${ACORN_SUBAGENT_RETRY_BUDGET:-1}"
  local retry_backoff="${ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS:-30}"
  ...
  cat <<'METHODOLOGY_EOF' \
    | sed "s|__SPEC_PATH__|${spec_path}|g" \
    | sed "s|__RETRY_BUDGET__|${retry_budget}|g" \
    | sed "s|__RETRY_BACKOFF__|${retry_backoff}|g" \
    ...
```

### New threshold env vars MUST follow the same ACORN_ prefix convention

For the 5-dim complexity score thresholds, the pattern would be:

```bash
ACORN_COMPLEXITY_HIGH_THRESHOLD="${ACORN_COMPLEXITY_HIGH_THRESHOLD:-12}"
ACORN_COMPLEXITY_MED_THRESHOLD="${ACORN_COMPLEXITY_MED_THRESHOLD:-8}"
ACORN_LOC_DECOMP_THRESHOLD="${ACORN_LOC_DECOMP_THRESHOLD:-800}"
ACORN_FILES_DECOMP_THRESHOLD="${ACORN_FILES_DECOMP_THRESHOLD:-8}"
```

These would be declared at the top of `bin/acorn` alongside the existing `ACORN_*` variables.

---

## Test Framework and Test File Conventions

### No external test framework

Tests are pure bash scripts. There is no bats, shunit2, or pytest for shell tests.

### Test file naming

All test files are in `test/` and named `test_<feature>.sh` (e.g., `test_split.sh`, `test_auto_trigger.sh`, `test_recon_completeness.sh`).

### Standard test harness boilerplate (copy exactly)

```bash
#!/usr/bin/env bash
set -euo pipefail

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
  if [ "$actual" = "$expected" ]; then
    pass "$name"
  else
    fail "$name" "expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    pass "$name"
  else
    fail "$name" "expected to contain '$needle'"
  fi
}

assert_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    fail "$name" "expected NOT to contain '$needle'"
  else
    pass "$name"
  fi
}
```

Shorter inline forms are also used (e.g., `test_recon_completeness.sh`):

```bash
assert_contains(){ local n="$1" h="$2" needle="$3"; printf '%s' "$h" | grep -qF -- "$needle" && pass "$n" || fail "$n" "missing $needle"; }
assert_eq(){ [ "$2" = "$3" ] && pass "$1" || fail "$1" "expected '$3' got '$2'"; }
```

### Key technique: source acorn functions without triggering main()

```bash
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"
```

This sources all function definitions. External commands (`claude`, `gh`, `tmux`, etc.) are then stubbed by overriding as bash functions and `export -f`.

### Function mocking pattern

```bash
claude() {
  cat <<'MOCK_EOF'
{"should_split":true,"reasoning":"test reason","sub_issues":[{"title":"A","scope":"scope A"}]}
MOCK_EOF
}
export -f claude
# ... run test ...
unset -f claude
```

### setup / teardown pattern

```bash
setup() {
  TMPDIR_BASE="$(mktemp -d)"
}

teardown() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE"
  unset -f gh 2>/dev/null || true
  unset -f claude 2>/dev/null || true
  # unset any other stubs
}
```

Using `trap 'rm -rf "$TMP"' EXIT` is the compact alternative (used in `test_recon_completeness.sh`).

### Negative control (prove-it-first) pattern

Tests that verify a function FAILS on bad input:

```bash
local exit_code=0
(analyze_issue_for_split "Test" "Body" "" "mock" >/dev/null 2>/dev/null) || exit_code=$?

if [ "$exit_code" -ne 0 ]; then
  pass "dies on invalid JSON response"
else
  fail "dies on invalid JSON response" "expected non-zero exit, got 0"
fi
```

For direct die() calls: use a subshell `( ... )` to capture without aborting the outer shell.

### Integration tests gated by env var

```bash
INTEGRATION="${INTEGRATION:-0}"
if [ "$INTEGRATION" = "1" ]; then
  # real network / tmux tests
fi
```

### Test summary footer (mandatory)

```bash
printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
```

### Test function naming

Named `test_<what_it_tests>()` or `test_<function>_<scenario>()`. E.g.:
- `test_format_recommendation_split()`
- `test_analyze_invalid_json()`
- `test_cmd_split_no_split()`
- `test_wait_for_claude_ready_timeout()`

Section headers use unicode box-drawing separators for readability:

```bash
printf '\n\033[1m== analyze_issue_for_split (raw JSON) ==\033[0m\n'
```

Or simpler:

```bash
echo "--- T1: test_output_empty_no_recon_dir ---"
```

---

## CI/CD Configuration and Quality Gates

No CI configuration file (`.github/workflows/`, `Makefile`, etc.) was found in the repository. Tests are run manually by executing the shell scripts directly:

```bash
bash test/test_split.sh
bash test/test_auto_trigger.sh
# etc.
```

The `bash -n "$ACORN_SCRIPT"` syntax check is used in `test_rt_gate_removal.sh` as a quality gate verifying the script is parseable:

```bash
set +e
bash -n "$ACORN_SCRIPT" 2>/dev/null
rc7=$?
set -e
assert_eq "bash -n passes" "$rc7" "0"
```

---

## Dependency Management

No package manager files (`package.json`, `requirements.txt`, `Gemfile`). Runtime dependencies are checked at call sites using `require_cmds`:

```bash
require_cmds() {
  local missing=()
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    die "Missing required command(s): ${missing[*]}"
  fi
}
```

Called before a command executes:

```bash
require_cmds gh jq tmux claude      # cmd_create
require_cmds gh jq claude           # cmd_issue_split
require_cmds python3 jq             # cmd_doctor
require_cmds curl                   # notify path
```

System dependencies: `bash`, `jq`, `gh` (GitHub CLI), `claude` (Claude CLI), `tmux`, `curl`, `python3`, `git`, `mktemp`, `sed`, `grep`, `find`, `iconv` (optional).

---

## Existing Abstractions and Utilities to Reuse

### analyze_issue_for_split() — line 3208

The existing split analysis function. It:
- Calls `claude -p --model "$model"` (one-shot headless) with a structured prompt
- Parses JSON from response (handles raw JSON, `\`\`\`json` fenced, generic fenced)
- Validates JSON structure with `jq -e 'has("should_split") and has("reasoning") and has("sub_issues")'`
- Returns JSON on stdout, info/warnings on stderr

The new complexity scorer will extend this by:
- Adding a `score` field and `dims` breakdown field to the JSON returned
- Extending the prompt to request the 5-dim score
- NOT breaking the existing `should_split`/`reasoning`/`sub_issues` contract

### render_prompt_md() — line 1803

Called during `acorn create`. It assembles the PROMPT.md file. This is where the complexity score must be surfaced at spec-authoring time (Requirement 1). The function takes `mode`, `spec_path`, `issue_json`, etc.

### planning_block_lite/full/quick() — lines 771, 1275, 1581

Generate the planning methodology block injected into PROMPT.md. Score surfacing may be placed immediately before this block in `render_prompt_md()`.

### validate_stage_artifacts() — line 162

Used by `acorn _internal validate-stage` to check stage outputs. The stage manifest (`stage_manifest()`) controls which artifacts are required per mode/stage.

### write_meta_json() — line 2180

Writes `meta.json` for each spec. Accepts `mode`, `output_mode` as params. Could be extended to write the complexity score.

### stage_manifest() — line 125

Maps pipeline mode+stage to expected artifact paths. New complexity artifacts don't need to be added to manifests (they're embedded in existing SPEC.md/PROMPT.md), but be aware this is where new artifact requirements would go.

### notify_telegram() / notify_foreman() — lines 43, 69

Fire-and-forget notification helpers. Used at key lifecycle events. Not needed for complexity scoring.

### slugify_title(), build_slug(), canonical_session_name() — utility helpers

Not relevant to complexity scoring.

---

## Key Patterns for the 5-Dim Complexity Score Feature

### Where to wire the score in the spec-authoring path

`render_prompt_md()` (line 1803) is called from `cmd_create()` (line 2524). The complexity scoring call should be added inside `render_prompt_md()` or immediately before it in `cmd_create()`, writing the score into the PROMPT.md header or into the spec directory's meta.json.

### How to extend analyze_issue_for_split() without breaking consumers

The existing JSON contract: `{"should_split": bool, "reasoning": str, "sub_issues": [...]}`.

Extension approach: add optional fields to the same JSON object:

```json
{
  "should_split": true,
  "reasoning": "...",
  "sub_issues": [...],
  "score": 12,
  "band": "HIGH",
  "dims": {
    "files_touched": 3,
    "loc_estimate": 2,
    "novelty": 2,
    "context_depth": 3,
    "cross_module_fan_out": 2
  },
  "decomposition_required": true,
  "atomic_justification": ""
}
```

Since `jq -e 'has("should_split") and has("reasoning") and has("sub_issues")'` is the only structural validator (line 3291), adding fields won't break validation.

### Env var naming for thresholds

Following `ACORN_*` prefix convention, declare at top of script alongside existing vars:

```bash
ACORN_COMPLEXITY_HIGH_THRESHOLD="${ACORN_COMPLEXITY_HIGH_THRESHOLD:-12}"
ACORN_COMPLEXITY_MED_THRESHOLD="${ACORN_COMPLEXITY_MED_THRESHOLD:-8}"
ACORN_LOC_DECOMP_THRESHOLD="${ACORN_LOC_DECOMP_THRESHOLD:-800}"
ACORN_FILES_DECOMP_THRESHOLD="${ACORN_FILES_DECOMP_THRESHOLD:-8}"
```

No bare magic numbers in the code body — every threshold accessed as `$ACORN_COMPLEXITY_HIGH_THRESHOLD` etc.

### Testing the new function

New test file: `test/test_complexity_score.sh`

Follow the exact harness pattern from `test_split.sh`:
1. `eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"` to source functions
2. Mock `claude` to return a fixture response with score fields
3. Test: HIGH-scored fixture → decomposition proposal triggered
4. Test: LOW/MED fixture → no decomposition proposal
5. Test: LOC > 800 threshold fires independently of band
6. Test: files > 8 threshold fires independently of band
7. Test: existing `analyze_issue_for_split` JSON contract still has `should_split`/`reasoning`/`sub_issues` — backward compatibility check
8. Negative controls: verify tests FAIL on the live-base before fix (per prove-it-first rule)

### Function naming for new scorer

Follow the `snake_case` internal helper convention:
- `score_spec_complexity()` — computes 5-dim score from issue content, returns JSON with score/band/dims
- `compute_complexity_band()` — maps numeric sum to LOW/MED/HIGH string, uses env threshold vars
- `check_size_thresholds()` — checks LOC/files vs decomp thresholds, returns flag

Or alternatively, extend `analyze_issue_for_split()` in-place by adding the scoring prompt to the existing Claude call.

---

## CLAUDE.md / AGENTS.md / Contributing Guidelines

No `CLAUDE.md` or `AGENTS.md` found in the repository root. The `.claude/skills/` directory contains skill definitions. The `UPSTREAM_PR.md` provides upstream contribution guidance:

- Changes are scoped strictly to the named subsystem (e.g., "Scope is intentionally limited to `bin/acorn`")
- "No forge-runtime/private repo coupling introduced"
- "Uses existing style conventions for heredoc rendering/substitution and gate routing"
- "Preserves existing call signatures and compatibility while adding metadata field safely"

The `forge-acorn-live-base` branch is the mandatory build base (commit d83a162).
