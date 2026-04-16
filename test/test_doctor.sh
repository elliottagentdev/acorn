#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Test harness for `acorn doctor` subcommand (W2-5).

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }
assert_eq() { local n="$1" a="$2" e="$3"; [ "$a" = "$e" ] && pass "$n" || fail "$n" "expected '$e', got '$a'"; }
assert_contains() { local n="$1" h="$2" ne="$3"; printf '%s' "$h" | grep -qF -- "$ne" && pass "$n" || fail "$n" "expected to contain '$ne'"; }
assert_not_contains() { local n="$1" h="$2" ne="$3"; printf '%s' "$h" | grep -qF -- "$ne" && fail "$n" "unexpected '$ne' in output" || pass "$n"; }

TMPDIR_BASE="$(mktemp -d)"
teardown() { rm -rf "$TMPDIR_BASE"; }
trap teardown EXIT

ACORN_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/acorn"
REAL_HANG_DETECT="/home/agentdev/.foreman/bin/hang-detect.sh"

export HOME="$TMPDIR_BASE"
export FOREMAN_HOME="$TMPDIR_BASE/.foreman"
export PROJECTS_DIR="$TMPDIR_BASE/projects"
mkdir -p "$FOREMAN_HOME/bin" "$PROJECTS_DIR"

# Stage the real hang-detect.sh into the sandbox FOREMAN_HOME
if [ -f "$REAL_HANG_DETECT" ]; then
    cp "$REAL_HANG_DETECT" "$FOREMAN_HOME/bin/hang-detect.sh"
    chmod +x "$FOREMAN_HOME/bin/hang-detect.sh"
fi

# Mock tmux
mkdir -p "$TMPDIR_BASE/bin"
cat > "$TMPDIR_BASE/bin/tmux" <<'MOCK'
#!/usr/bin/env bash
# Mock: all sessions dead unless MOCK_TMUX_ALIVE=1
if [ "${MOCK_TMUX_ALIVE:-0}" = "1" ] && [ "${1:-}" = "has-session" ]; then
    exit 0
fi
exit 1
MOCK
chmod +x "$TMPDIR_BASE/bin/tmux"
export PATH="$TMPDIR_BASE/bin:$PATH"

# Source acorn to pick up helpers (session_state, spec_root, notify_telegram, etc.)
# without executing main. Strip the trailing `main "$@"` invocation.
eval "$(sed '/^main "\$@"$/d' "$ACORN_SCRIPT")"

# Override PROJECTS_DIR to point at our sandbox.
# (The export on line 23 now takes effect via ${PROJECTS_DIR:-...} default syntax,
# but this explicit override is kept for clarity.)
PROJECTS_DIR="$TMPDIR_BASE/projects"

# Override notify_telegram to capture calls in-process
TELEGRAM_CAPTURE_FILE="$TMPDIR_BASE/telegram.log"
notify_telegram() {
    printf '%s\n' "$1" >> "$TELEGRAM_CAPTURE_FILE"
}
export -f notify_telegram 2>/dev/null || true

# ---- TD1: No active sessions ----
printf '\n== TD1: No active sessions ==\n'
mkdir -p "$PROJECTS_DIR/testrepo/main/.specs"
set +e
out=$(cmd_doctor "testrepo" 2>&1)
rc=$?
set -e
assert_contains "TD1 no active sessions" "$out" "No active Acorn sessions"
assert_eq "TD1 exit code (no sessions = 1)" "$rc" "1"

# ---- TD2: Stalled session detected ----
printf '\n== TD2: Stalled session ==\n'
slug="99-test-slug"
spec_dir="$PROJECTS_DIR/testrepo/main/.specs/$slug"
mkdir -p "$spec_dir/recon"
echo "old" > "$spec_dir/recon/file.md"
cat > "$spec_dir/meta.json" <<EOF
{"repo":"testrepo","issue_number":99,"slug":"$slug","session_name":"testrepo_specs_${slug}_claude","mode":"lite"}
EOF
# Backdate every file under the spec dir so hang-detect sees a stalled session.
# (meta.json must also be backdated, otherwise it becomes the newest file.)
find "$spec_dir" -type f -exec touch -d "60 minutes ago" {} +

export MOCK_TMUX_ALIVE=1
: > "$TELEGRAM_CAPTURE_FILE"
set +e
out=$(cmd_doctor "testrepo" 2>&1)
rc=$?
set -e
assert_contains "TD2 stalled detected" "$out" "stalled"
assert_eq "TD2 exit code (hangs = 0)" "$rc" "0"

# ---- TD3: Repo filter works ----
printf '\n== TD3: Repo filter ==\n'
mkdir -p "$PROJECTS_DIR/other/main/.specs/10-other/recon"
echo "x" > "$PROJECTS_DIR/other/main/.specs/10-other/recon/f.md"
cat > "$PROJECTS_DIR/other/main/.specs/10-other/meta.json" <<'EOF'
{"repo":"other","issue_number":10,"slug":"10-other","session_name":"other_specs_10-other_claude","mode":"quick"}
EOF
set +e
out=$(cmd_doctor "testrepo" 2>&1)
set -e
# Filtered output should mention the testrepo slug but not "10-other"
assert_contains "TD3 filtered has testrepo" "$out" "99-test-slug"
assert_not_contains "TD3 filtered excludes other" "$out" "10-other"

# ---- TD4: Telegram notification on hangs ----
printf '\n== TD4: Telegram notification ==\n'
: > "$TELEGRAM_CAPTURE_FILE"
# Run in a subshell -- cmd_doctor calls `exit 0` on hang, which would kill
# the test harness otherwise. Export the helper + capture path so the
# subshell can still reach them.
export TELEGRAM_CAPTURE_FILE
export -f notify_telegram
( cmd_doctor "testrepo" >/dev/null 2>&1 ) || true
if [ -s "$TELEGRAM_CAPTURE_FILE" ]; then
    telegram_msg="$(cat "$TELEGRAM_CAPTURE_FILE")"
    assert_contains "TD4 telegram sent" "$telegram_msg" "appear hung"
else
    fail "TD4 telegram sent" "notify_telegram was not invoked (capture file empty)"
fi

unset MOCK_TMUX_ALIVE

printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
