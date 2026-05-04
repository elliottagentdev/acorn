# Acorn Conventions & Constraints

## Directory Structure

```
/home/agentdev/projects/acorn/main/
  bin/acorn            # Symlink or copy of the real script in ~/.local/bin/acorn
  test/                # All test scripts live here (no subdirectories)
    test_*.sh          # Naming convention: test_<feature>.sh
  claude/
    global/CLAUDE.md   # Project-level CLAUDE.md (Acorn pipeline docs)
  evals/               # Eval harness JSON files
  README.md

/home/agentdev/.local/bin/acorn  # Primary executable (3690 lines, single bash file)
```

The entire product is **one bash file** (`/home/agentdev/.local/bin/acorn`). There is no separate library, no `source` of helper files. All functions are defined at the top level of the file and `main "$@"` is the last line.

---

## Bash Style Conventions

### Shebang and Strict Mode

Every script (main binary and all tests) uses the same header:

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
```

`IFS=$'\n\t'` is set at the top level of the main binary (line 3) to prevent word-splitting on spaces. Tests also use `set -euo pipefail` but some omit the `IFS` override.

### Function Naming

- **All lowercase, underscores**: `cmd_create`, `notify_telegram`, `require_cmds`, `build_slug`, `safe_repo_main`
- **Command handlers**: prefixed `cmd_` (e.g., `cmd_create`, `cmd_list`, `cmd_approve`, `cmd_clean`, `cmd_doctor`)
- **Private helpers**: no prefix, descriptive names (e.g., `spec_root`, `spec_dir`, `canonical_session_name`, `slugify_title`)
- **Notification helpers**: `notify_telegram`, `notify_foreman`
- **Sub-command structure**: `cmd_issue_create`, `cmd_issue_split`, `cmd_issue_clarify`, `cmd_issue_depends`

### Local Variables

Every function declares variables with `local`:

```bash
cmd_create() {
  local repo="$1"
  local issue_number="$2"
  shift 2
  local auto_trigger=1
  local mode="full"
  ...
}
```

Parameters are shifted after assignment: `shift 2` follows `local repo="$1"; local issue_number="$2"`.

### Flag Parsing Pattern

All commands that accept flags use a `while [ "$#" -gt 0 ]; do case "$1"` loop:

```bash
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-auto)
      auto_trigger=0
      ;;
    --lite)
      [ "$mode" = "full" ] || die "--lite and --quick are mutually exclusive"
      mode="lite"
      ;;
    *)
      die "Unknown option for create: $1"
      ;;
  esac
  shift
done
```

Unknown flags always call `die` with a descriptive message.

### Output / printf Convention

- **`printf` everywhere, never `echo`** for user-facing output in library functions
- `info()` uses `printf '[INFO] %s\n' "$*"` to stdout
- `warn()` uses `printf '[WARN] %s\n' "$*" >&2` to stderr
- `die()` uses `printf '[ERROR] %s\n' "$*" >&2; exit 1`
- User-facing non-log output in `cmd_*` functions uses bare `printf` or `echo` (echo is used sparingly for simple output lines in cmd functions, e.g., `echo "Created spec: $dir"`)

The three logging primitives (defined near line 35-37):
```bash
info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
```

### String Handling

- **Use `printf '%s' "$var"` rather than `echo "$var"`** when piping to avoid echo's interpretation of escape sequences
- Multi-line strings use heredocs (`<<'EOF'`) for literal content
- No use of `echo -e`; escape sequences are embedded directly or via `$'\n'`
- Bash string replacement syntax used (`${result//"$original"/$replacement}`) instead of sed for simple substitutions

### Subshell Isolation

Fire-and-forget background operations always use a subshell with `disown`:

```bash
(
  # background work
  curl ...
) &
disown
```

This pattern is used in `notify_telegram`, `notify_foreman`, `register_with_forged`, and `send_auto_trigger`.

---

## Error Handling Patterns

### Primary Pattern: `die` on unrecoverable errors

```bash
[ -d "$dir" ] || die "Spec directory missing: $dir"
[ -f "$dir/plans/SPEC.md" ] || die "Missing final plan: $dir/plans/SPEC.md"
```

### Soft failures: `warn` + `|| true`

Non-critical operations use `|| true` or `|| warn`:

```bash
gh issue edit "$issue_number" --repo "$nwo" --remove-label "$label" >/dev/null 2>&1 \
  || warn "Unable to remove label '$label' from issue #$issue_number"
```

### set +e / set -e around fallible calls

When a command may legitimately fail and its exit code must be captured:

```bash
set +e
response="$(curl -fsS --max-time 3 "$forged_url" 2>/dev/null)"
local ec=$?
set -e

if [ $ec -ne 0 ]; then
  warn "Forged not reachable -- skipping circuit breaker check (fail-open)"
  return 0
fi
```

This pattern is used throughout for network calls and external tool invocations.

### Temp file cleanup

Temp files are created with `mktemp` and cleaned up explicitly or via `trap`:

```bash
local stderr_file
stderr_file="$(mktemp)" || die "Failed to create temp file for stderr capture"
# ... use it ...
rm -f "$stderr_file"
```

Atomic file writes use write-to-tmp then move:

```bash
local tmp_path="$prompt_path.tmp"
render_prompt_md ... "$tmp_path" ...
if ! validate_prompt_md "$tmp_path"; then
  rm -f "$tmp_path"
  die "Prompt generation failed: planning anchor missing"
fi
mv "$tmp_path" "$prompt_path"
```

### Validation before destructive ops

Before `rm -rf`, a path-safety check is performed:

```bash
case "$target" in
  "$root"/*) ;;
  *) die "Unsafe clean target path: $target" ;;
esac
```

---

## Test Framework and Patterns

### Test File Naming

All tests are in `/home/agentdev/projects/acorn/main/test/test_*.sh` (bash scripts, no `.bats`). No external test framework (no bats, no shunit2). All tests are hand-rolled bash.

### Test Harness Pattern

Each test file defines its own `pass/fail/assert_*` helpers, consistent across files:

```bash
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

assert_not_contains() { ... }  # Inverse of assert_contains
```

### Sourcing the Binary Without Executing main()

Tests source the acorn binary by stripping the final `main "$@"` invocation via sed:

```bash
ACORN_SCRIPT="$SCRIPT_DIR/bin/acorn"
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"
```

This makes all internal functions available without launching the CLI.

### Mocking External Dependencies

External commands (`gh`, `tmux`, `curl`, `claude`) are mocked with bash function overrides and `export -f`:

```bash
gh() {
  echo '{"number":1,"title":"Test","body":"...","labels":[]}'
}
export -f gh
```

After test: `unset -f gh safe_repo_main require_cmds ...`

### Setup/Teardown Pattern

Each test file has `setup()` and `teardown()` functions, and many use `trap`:

```bash
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

setup() {
  TMPDIR_BASE="$(mktemp -d)"
}

teardown() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE"
  unset -f gh 2>/dev/null || true
}
```

### Integration vs Unit Test Gating

Integration tests are gated by env var:

```bash
INTEGRATION="${INTEGRATION:-0}"
if [ "$INTEGRATION" = "1" ]; then
  test_integration_...
else
  printf '\nSkipping integration tests (run with INTEGRATION=1 to enable)\033[0m\n'
fi
```

### Test Summary Line

Every test file ends with:

```bash
printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
```

### Behavioral Tests (Pattern Scanning)

Some tests verify correctness by grepping the source directly:

```bash
if grep -qF "auth-check.sh" "$ACORN_SCRIPT" 2>/dev/null; then
  pass "BH1 acorn auth gate reference exists"
else
  fail "BH1 acorn auth gate reference exists" "auth-check.sh not found in acorn script"
fi
```

---

## Environment Variable Conventions

### Naming

- All-caps, underscore-separated: `PROJECTS_DIR`, `FOREMAN_HOME`, `TELEGRAM_NOTIFY_PORT`, `TELEGRAM_NOTIFY_URL`
- New env vars for this feature should follow: `ACORN_SUBAGENT_RETRY_BUDGET`, `ACORN_FAILURE_EVENT_PATH`

### Default Value Pattern

All env vars use `${VAR:-default}` syntax:

```bash
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"
TELEGRAM_NOTIFY_PORT="${TELEGRAM_NOTIFY_PORT:-8765}"
FOREMAN_HOME="${FOREMAN_HOME:-$HOME/.foreman}"
```

### Forge-specific Env Vars

Forge-integration env vars use the `FOREMAN_HOME` prefix for paths:

```bash
local auth_check="${FOREMAN_HOME:-$HOME/.foreman}/bin/auth-check.sh"
local watchdog_state="${FOREMAN_HOME:-$HOME/.foreman}/watchdog-state"
```

New event-path env vars follow this pattern: set in Forge but have sensible `:-""` defaults that disable the feature when not set.

---

## Dependency Management

### External Tool Dependencies

Checked via `require_cmds` before use:

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

Each command function calls `require_cmds` at the top with its dependencies:

```bash
cmd_create() {
  ...
  require_cmds gh jq tmux claude
  ...
}
```

### Core Dependencies

- `bash` (4.x+), `jq`, `gh` (GitHub CLI), `tmux`, `claude` (Claude Code CLI)
- `curl` for HTTP (notification, circuit breaker)
- Optional: `python3` (for `cmd_doctor`), `iconv` (for slug generation)

### No Package Manager

There is no `package.json`, `requirements.txt`, `Gemfile`, etc. The script installs nothing — it assumes all tools are pre-installed on the host.

---

## Existing Abstractions to Reuse

### Logging

```bash
info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
```

All new code must use these exclusively for user-visible messages.

### Path Helpers

```bash
spec_root()  # ~/.../main/.specs
spec_dir()   # ~/.../main/.specs/<slug>
safe_repo_main()  # Validates and returns repo/main path
```

### Event Emission: `notify_foreman`

```bash
notify_foreman "event.type" "human message" "$session" "$extra_json"
```

This is the existing hook for emitting structured events. The new `ACORN_FAILURE_EVENT_PATH` JSONL feature should be modeled after this — a separate code path that appends directly to a file rather than going through the HTTP endpoint.

### Notification: `notify_telegram`

Fire-and-forget Telegram notification. Always best-effort, never blocking.

### Requirement Validation Pattern

The existing `validate_prompt_md` function is the closest existing analog to what the new artifact validation gate should do:

```bash
validate_prompt_md() {
  local prompt_path="$1"
  grep -q 'PLANNING METHODOLOGY — MANDATORY INSTRUCTIONS' "$prompt_path" || return 1
  return 0
}
```

New stage validation should follow this same pattern: a function that checks existence, non-emptiness, and required section headers, returning non-zero on failure.

---

## CI/CD Configuration

There is **no CI/CD configuration file** in the repository (no `.github/workflows/`, no `Makefile`, no `Dockerfile`). Tests are run manually:

```bash
bash test/test_split.sh
bash test/test_labels.sh
INTEGRATION=1 bash test/test_split.sh
```

No automated test runner (no `npm test`, no pytest invocation, no pre-commit hooks visible in the repo). The dev workflow relies on running tests directly before committing.

---

## CLAUDE.md / Contributing Guidelines

### Project CLAUDE.md

`/home/agentdev/projects/acorn/main/claude/global/CLAUDE.md` documents the acorn pipeline modes, commands, spec directory layout, status values, and label lifecycle. It is a reference document for Claude sessions operating within the acorn project, not a contributing guide.

### No CONTRIBUTING.md or AGENTS.md

There is no `CONTRIBUTING.md`, `AGENTS.md`, or `.github/CONTRIBUTING.md` in the repository.

### Implicit Conventions from Commit History and Code

1. **Single-file design is intentional**: all logic stays in `/home/agentdev/.local/bin/acorn`; do not introduce separate library files
2. **Forge features use conditional hooks**: forge-specific behavior is always guarded by `if [ -x "$script" ]` or `if [ -d "$dir" ]` checks; upstream callers without forge infrastructure simply skip those paths
3. **No new global state**: the global variables at the top (`SCRIPT_NAME`, `PROJECTS_DIR`, `LIFECYCLE_LABELS`, etc.) are initialized once; new env-var-based config follows the `VAR="${VAR:-default}"` pattern
4. **Write tests for each new function**: test files map one-to-one with features (test_split.sh for split, test_labels.sh for labels, test_auth_preflight.sh for auth gate, etc.)

---

## Key Patterns for the New Feature

### Artifact Validation Gate (Pattern)

New stage-completion validation should follow the `validate_prompt_md` template but check existence + non-emptiness + required headers:

```bash
validate_stage_artifacts() {
  local stage="$1"
  local spec_dir="$2"
  # Returns 0 if valid, 1 if missing/empty/invalid
  local file
  for file in ...; do
    [ -f "$spec_dir/$file" ] || return 1
    [ -s "$spec_dir/$file" ] || return 1
    grep -q "## Expected Header" "$spec_dir/$file" || return 1
  done
  return 0
}
```

### JSONL Event Emission (Pattern)

New `ACORN_FAILURE_EVENT_PATH` emission should follow the `write_meta_json` approach (jq -n to build, redirect to file):

```bash
emit_failure_event() {
  local event_path="${ACORN_FAILURE_EVENT_PATH:-}"
  [ -n "$event_path" ] || return 0
  local payload
  payload="$(jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg slug "$slug" \
    --arg stage "$stage" \
    ...
    '{ts: $ts, slug: $slug, ...}')"
  printf '%s\n' "$payload" >> "$event_path" 2>/dev/null || true
}
```

### Retry Loop Pattern (Pattern)

The existing `wait_for_claude_ready` function shows the idiomatic retry-with-timeout loop style:

```bash
local elapsed=0
while [ "$elapsed" -lt "$max_wait" ]; do
  # attempt
  if <condition>; then
    return 0
  fi
  sleep "$interval"
  elapsed=$((elapsed + interval))
done
return 1
```

New sub-agent retry should follow this with a budget counter instead of time:

```bash
local retry=0
local max_retries="${ACORN_SUBAGENT_RETRY_BUDGET:-1}"
while [ "$retry" -le "$max_retries" ]; do
  # launch agent
  if validate_stage_artifacts ...; then
    return 0
  fi
  retry=$((retry + 1))
  [ "$retry" -le "$max_retries" ] && sleep "${ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS:-30}"
done
# halted
```

### Stderr Diagnostic Pattern

Diagnostic output on halt should use `warn` and follow the existing verbose multi-line warning style:

```bash
warn "Stage halted: $stage"
warn "  Agent: $agent_name"
warn "  Expected artifact: $artifact_path"
warn "  Observed: $([ -f "$artifact_path" ] && printf 'exists but empty' || printf 'missing')"
warn "  Last 50 lines of output:"
tail -n 50 "$agent_log" >&2 2>/dev/null || true
warn "  Suggested action: acorn clean $repo $slug --force && acorn create $repo $issue_number"
```
