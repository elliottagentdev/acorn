# Conventions & Constraints Reconnaissance

## Project Overview

Acorn is a single-file Bash CLI (`bin/acorn`). The entire codebase is one ~3600-line Bash script. There is no build system, no package manager, no compiled language. All conventions are Bash-native.

---

## Coding Style & Naming Conventions

### Shell Header

Every file begins with:
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
```

`IFS=$'\n\t'` is set at the top of `bin/acorn` to protect against word splitting. Some test files omit it.

### Variable Naming

- **Global constants**: `UPPER_SNAKE_CASE`  
  Examples: `SCRIPT_NAME`, `PROJECTS_DIR`, `LIFECYCLE_LABELS`, `TELEGRAM_NOTIFY_PORT`, `TELEGRAM_NOTIFY_URL`
- **Local variables**: `lower_snake_case` always declared with `local`  
  Examples: `local repo_main`, `local issue_number`, `local spec_path`
- **Loop/temp variables**: single-letter or short descriptive names  
  Examples: `local cmd`, `local label`, `local r`
- **Private/internal globals with underscore prefix** used for function state:  
  Examples: `_SHOW_DEPS=0`, `_LIST_NWO=""`

### Function Naming

- **Command handlers**: `cmd_<subcommand>` pattern  
  Examples: `cmd_create`, `cmd_list`, `cmd_approve`, `cmd_spec_complete`, `cmd_clean`, `cmd_doctor`
- **Sub-command handlers**: `cmd_issue_<action>` pattern  
  Examples: `cmd_issue_create`, `cmd_issue_plan`, `cmd_issue_clarify`, `cmd_issue_split`, `cmd_issue_depends`
- **Helper functions**: descriptive `lower_snake_case`  
  Examples: `build_slug`, `slugify_title`, `canonical_session_name`, `safe_repo_main`, `repo_main_path`, `spec_root`, `spec_dir`, `gh_repo_nwo`
- **Utility functions**: `<action>_<noun>` or `<noun>_<action>`  
  Examples: `notify_telegram`, `notify_foreman`, `write_meta_json`, `human_age`, `file_mtime_epoch`
- **Print/display helpers**: `print_<thing>` or `render_<thing>`  
  Examples: `print_list_header`, `print_list_row`, `print_status_header`, `render_prompt_md`, `render_comments_block`

### Output Conventions

Three logging levels, all to stderr except `info` which goes to stdout for informational messages:
```bash
info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
```
- `info` — normal progress messages, stdout
- `warn` — non-fatal issues, stderr, continues execution
- `die` — fatal, exits immediately with code 1

Output to user (not log): plain `echo` or `printf` without tag prefix.  
Example from `cmd_create`:
```bash
echo ""
echo "Created spec: $dir"
echo "Mode: $mode"
echo "Session: $session_name"
```

### Printf vs Echo

**Strongly prefer `printf`** over `echo` for all formatted output and variable content:
```bash
printf '[INFO] %s\n' "$*"
printf '%s' "$slug"
printf '%s\n' "$session_name"
```
`echo` is used only for simple user-facing status lines within `cmd_*` functions.

---

## Error Handling Patterns

### Guard Clauses

Every command function validates inputs early using guard clauses:
```bash
[ -d "$dir" ] || die "Spec directory missing: $dir"
[ -f "$dir/plans/SPEC.md" ] || die "Missing final plan: $dir/plans/SPEC.md"
[ -n "$issue_number" ] || die "Cannot infer issue number from slug: $slug"
```

### Soft vs Hard Failures

- **Hard fail** (`die`): unrecoverable conditions (missing required files, invalid args, auth failures)
- **Soft fail** (`warn` + return/continue): degraded operation is acceptable (label operations, notifications)

Pattern for soft failures with fallback:
```bash
gh issue edit "$issue_number" --repo "$nwo" --remove-label "$label" >/dev/null 2>&1 \
  || warn "Unable to remove label '$label' from issue #$issue_number"
```

Pattern for hard failures:
```bash
gh issue edit "$issue_number" --repo "$nwo" --add-label "$label" >/dev/null \
  || die "Failed adding label '$label' on issue #$issue_number"
```

### Fail-Open Pattern for External Services

External services (Forged daemon, Telegram bridge, circuit breaker) use fail-open: if the service is unreachable, warn and continue:
```bash
check_circuit_breaker() {
  ...
  if [ $ec -ne 0 ]; then
    warn "Forged not reachable -- skipping circuit breaker check (fail-open)"
    return 0
  fi
  ...
}
```

### Subshell Fire-and-Forget

Network calls (Telegram notifications, Forged registration) run in background subshells with `disown` to avoid blocking:
```bash
(
  curl -fsS --max-time 5 ... || true
) &
disown
```
The `|| true` inside the subshell ensures the subshell never exits non-zero.

### Temp File Pattern

Atomic writes use temp files + `mv`:
```bash
local tmp_path="$prompt_path.tmp"
render_prompt_md ... > "$tmp_path"
validate_prompt_md "$tmp_path" || { rm -f "$tmp_path"; die "..."; }
mv "$tmp_path" "$prompt_path"
```

---

## Test Framework

### No External Framework

Tests are plain Bash scripts. No bats, no shunit2, no pytest. The test framework is hand-rolled in each test file.

### Test File Naming

All test files in `test/` directory, named `test_<feature>.sh`:
- `test/test_images.sh`
- `test/test_labels.sh`
- `test/test_auto_trigger.sh`
- `test/test_split.sh`
- `test/test_dependencies.sh`
- `test/test_auth_preflight.sh`
- `test/test_doctor.sh`
- `test/test_idle_detect.sh`
- `test/test_idle_e2e.sh`
- `test/test_notify.sh`
- `test/test_concurrent_launch.sh`
- `test/test_path_npm_global.sh`

### Standard Test Boilerplate

Every test file follows this structure:
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACORN_SCRIPT="$SCRIPT_DIR/bin/acorn"

# Source acorn functions without triggering main()
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"

PASS=0
FAIL=0
```

**Key technique**: `eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"` sources all acorn functions into the test shell without executing `main`. This allows direct unit testing of individual functions.

### Test Helpers (Standard Set)

Always present across all test files:
```bash
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
```

Some tests also define `assert_file_exists`, `assert_file_not_empty`, `assert_dir_empty`.

Note: `test_images.sh` uses `(haystack, needle, label)` arg order while most others use `(name, haystack, needle)`. This is an inconsistency in the existing codebase.

### Mocking Pattern

Functions are overridden using Bash function declarations + `export -f`:
```bash
gh() { echo '[{"number":5}]'; }
export -f gh

safe_repo_main() { echo "/tmp/repo"; }
export -f safe_repo_main
```

Cleanup in `teardown()` uses `unset -f`:
```bash
teardown() {
  unset -f gh safe_repo_main set_issue_state_label 2>/dev/null || true
}
```

### Setup/Teardown Pattern

```bash
TMPDIR_BASE=""

setup() {
  TMPDIR_BASE="$(mktemp -d)"
}

teardown() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE"
  unset -f gh ... 2>/dev/null || true
}
```

For tests needing cleanup on exit: `trap teardown EXIT`

### Test Function Naming

```bash
test_<what_is_being_tested>() {
  printf '\n\033[1m== <description> ==\033[0m\n'
  ...
}
```

### Integration Test Guard

Tests that call the real GitHub API are gated behind `INTEGRATION`:
```bash
INTEGRATION="${INTEGRATION:-0}"
if [ "$INTEGRATION" = "1" ]; then
  test_integration_...
else
  printf '\n\033[2mSkipping integration tests (run with INTEGRATION=1 to enable)\033[0m\n'
fi
```

### Test Execution Pattern

Functions are called sequentially at the bottom of the file:
```bash
setup
test_foo
setup  # reset between tests
test_bar
...
teardown

printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
```

### Running Tests

```bash
# Unit tests (no GitHub API)
bash test/test_images.sh
bash test/test_labels.sh
bash test/test_split.sh
bash test/test_dependencies.sh

# With integration tests
INTEGRATION=1 bash test/test_images.sh
```

---

## CI/CD Configuration

**No CI/CD pipeline exists** in this repository. No `.github/workflows/`, no `Makefile`, no `Dockerfile`. Tests are run manually.

---

## Dependency Management

### Runtime Dependencies (External Commands)

Checked at runtime using `require_cmds`:
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

Called at the top of each command function:
```bash
require_cmds gh jq tmux claude
require_cmds gh jq
require_cmds jq
```

Required external tools: `gh` (GitHub CLI), `jq`, `tmux`, `claude` (Claude Code CLI), `curl`

Optional tools checked with `command -v ... >/dev/null 2>&1`: `iconv`, `md5`, `md5sum`, `cksum`

### No Package Manager

No `npm`, `pip`, `gem`, or any package manager. The script has zero library dependencies beyond standard Unix tools.

### PATH Management

The script prepends npm-global to PATH for non-interactive shells (where `claude` binary lives):
```bash
export PATH="/home/agentdev/.npm-global/bin${PATH:+:$PATH}"
```
With defense-in-depth warning if `claude` resolves elsewhere.

---

## Existing Abstractions & Utilities to Reuse

### Path Helpers

```bash
repo_main_path()   # ~/projects/<repo>/main OR ~/projects/<repo>
spec_root()        # <repo_main>/.specs
spec_dir()         # <repo_main>/.specs/<slug>
safe_repo_main()   # validates and returns repo_main path, dies if missing
```

### Slug Helpers

```bash
slugify_title()          # "My Feature Title" -> "my-feature-title"
build_slug()             # "<issue#>-<slug>" -> "42-my-feature-title"
canonical_session_name() # "<repo>_specs_<slug>_claude"
issue_number_from_slug() # "42-my-feature-title" -> "42"
```

### GitHub Helpers

```bash
gh_repo_nwo()        # returns "owner/repo" from git remote
gh_issue_json()      # fetches issue JSON with title, body, labels, comments
ensure_labels()      # creates lifecycle labels if missing
set_issue_state_label()  # transitions lifecycle label
set_clarification_label() # transitions clarification label
comment_issue()      # posts a comment on the issue
```

### Session Management

```bash
start_session()          # creates tmux session
send_auto_trigger()      # sends planning trigger to session
wait_for_claude_ready()  # polls until Claude Code shows prompt
kill_session()           # kills tmux session
session_state()          # returns "running", "dead", or "no-session"
```

### Metadata

```bash
write_meta_json()    # writes meta.json to spec dir
file_mtime_epoch()   # cross-platform file mtime (macOS + Linux)
human_age()          # "42s", "5m", "2h", "3d" from epoch
```

### Notification

```bash
notify_telegram()    # fire-and-forget Telegram notification
notify_foreman()     # fire-and-forget Foreman event (falls back to Telegram)
```

### Planning Block Generators

These functions generate the planning methodology markdown embedded in PROMPT.md:
```bash
planning_block()       # dispatcher for full/lite/quick
planning_block_full()  # full pipeline methodology
planning_block_lite()  # lite pipeline methodology  
planning_block_quick() # quick pipeline methodology
```
All three use `sed "s|__SPEC_PATH__|${spec_path}|g"` to inject the spec path into the template.

### auto_trigger_message()

Generates the trigger message sent to the Claude session:
```bash
auto_trigger_message() {
  local spec_path="$1"
  local mode="${2:-full}"
  case "$mode" in
    full)  printf 'Read %s/PROMPT.md and follow ALL instructions...' "$spec_path" ;;
    lite)  printf '...' ;;
    quick) printf '...' ;;
  esac
}
```

---

## Key Patterns for the Three-Artifact Feature

### How to Check Mode

The current mode is stored in `meta.json` and read via jq:
```bash
mode="$(jq -r '.mode // "full"' "$dir/meta.json" 2>/dev/null || printf 'full')"
```

In `cmd_create`, mode is a local variable:
```bash
local mode="full"
# Set by --lite or --quick flags
```

### How to Add Env Var Support

Pattern from existing code (PROJECTS_DIR, TELEGRAM_NOTIFY_PORT):
```bash
SOME_VAR="${SOME_VAR:-default_value}"
```
For the new `ACORN_OUTPUT_MODE` env var:
```bash
ACORN_OUTPUT_MODE="${ACORN_OUTPUT_MODE:-single}"
```

### Where to Add PLAN.md / TASKS.md Warnings

`cmd_approve()` and `cmd_spec_complete()` (lines ~2392-2468) are the right locations for the AC6 warnings. Current pattern checks for SPEC.md with `die`; warnings would use `warn`:
```bash
# Current:
[ -f "$dir/plans/SPEC.md" ] || die "Missing final plan: $dir/plans/SPEC.md"

# Pattern for three-artifact warnings (warn, not die):
if [ "${ACORN_OUTPUT_MODE:-single}" = "three-artifact" ]; then
  [ -f "$dir/plans/PLAN.md" ] || warn "Missing PLAN.md in three-artifact mode"
  [ -f "$dir/plans/TASKS.md" ] || warn "Missing TASKS.md in three-artifact mode"
fi
```

### Where Prompts Are Generated

The planning prompt text is generated in `planning_block_full()`, `planning_block_lite()`, and `planning_block_quick()` (lines ~673-1607). The Final Spec agent prompt within each function (the last `cat <<'METHODOLOGY_EOF'` block in each) is where three-artifact output instructions would be added.

The key agent prompt in lite mode is at approximately line 1345-1400 (Stage 3: Final Spec).

### Render Pipeline

`render_prompt_md()` (line ~1621) assembles PROMPT.md, calling `planning_block()` to inject methodology. This is where the mode-specific planning instructions are embedded.

---

## CLAUDE.md / AGENTS.md / Contributing Guidelines

### `/home/agentdev/projects/acorn/main/claude/global/CLAUDE.md`

Global context installed into `~/.claude/CLAUDE.md`. Documents the acorn CLI for Claude operators. No implementation conventions.

### No AGENTS.md or CONTRIBUTING.md

No contributing guidelines file exists.

### `.claude/skills/` Directory

Contains four skill subdirectories: `issue-craft`, `orchestrate`, `setup`, `spec-review`. These are Claude Code skills (markdown prompt files + eval JSON), not Bash code.

---

## Summary of Key Conventions

1. **Single-file Bash** — all logic in `bin/acorn`, no modules, no libraries
2. **`set -euo pipefail` + `IFS=$'\n\t'`** at top of every script
3. **`local` for all function variables** — no global mutation inside functions
4. **`printf` over `echo`** for formatted/variable output
5. **`info/warn/die` logging** — info=stdout, warn/die=stderr
6. **Guard-clause style** — validate inputs early with `[ condition ] || die/warn`
7. **Fail-open for external services** — Forged, Telegram, circuit breaker
8. **Atomic writes** — temp file + mv pattern for file creation
9. **Fire-and-forget** — background subshell + disown for notifications
10. **Test by sourcing** — `eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"` 
11. **No external test framework** — hand-rolled `pass/fail/assert_*` in each test file
12. **Mock with function override** — `gh() { ... }; export -f gh`
13. **Integration tests gated** — `INTEGRATION="${INTEGRATION:-0}"` env var
14. **No CI pipeline** — tests run manually
15. **No dependencies** — zero npm/pip/gem, only standard Unix + external CLIs
