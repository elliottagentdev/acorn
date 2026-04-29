#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Test: acorn exports /home/agentdev/.npm-global/bin onto PATH so that
# `claude` resolves in non-interactive shells (regression for issue #109).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACORN_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/bin/acorn"

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  PASS %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s -- %s\n' "$1" "$2"; }
assert_eq() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "expected '$3', got '$2'"; }
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "expected '$2' to contain '$3'" ;;
  esac
}

REAL_HOME="$HOME"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# --- Test 1: top-level export line is present in the script ---
# Match the `${PATH:+:$PATH}` form chosen in §2.4 / R-4 mitigation.
if grep -Fq 'export PATH="/home/agentdev/.npm-global/bin${PATH:+:$PATH}"' "$ACORN_SCRIPT"; then
  pass "export-line-present"
else
  fail "export-line-present" "did not find the expected export PATH line in $ACORN_SCRIPT"
fi

# --- Test 1b: defense-in-depth warn-check is present (R-1b mandatory mitigation) ---
if grep -Fq 'claude resolved to unexpected path' "$ACORN_SCRIPT"; then
  pass "warn-check-present"
else
  fail "warn-check-present" "did not find the R-1b PATH-hijack warn-check in $ACORN_SCRIPT"
fi

# --- Test 2: sourcing acorn in a minimal-PATH subshell prepends npm-global/bin ---
# Simulates a non-interactive background spawn (Foreman -> acorn).
NEW_PATH="$(
  env -i HOME="$REAL_HOME" PATH="/usr/bin:/bin" bash -c '
    set -euo pipefail
    eval "$(sed "/^main \"\\\$@\"/d" "'"$ACORN_SCRIPT"'")"
    printf "%s" "$PATH"
  '
)"
assert_contains "non-interactive-prepends-npm-global" "$NEW_PATH" "/home/agentdev/.npm-global/bin"
case "$NEW_PATH" in
  /home/agentdev/.npm-global/bin:*) pass "non-interactive-prepended-not-appended" ;;
  *) fail "non-interactive-prepended-not-appended" "expected PATH to start with /home/agentdev/.npm-global/bin, got: $NEW_PATH" ;;
esac

# --- Test 3: sourcing acorn when the dir is already on PATH still works (no error, idempotent prepend) ---
INTERACTIVE_PATH="$(
  env -i HOME="$REAL_HOME" PATH="/home/agentdev/.npm-global/bin:/usr/bin:/bin" bash -c '
    set -euo pipefail
    eval "$(sed "/^main \"\\\$@\"/d" "'"$ACORN_SCRIPT"'")"
    printf "%s" "$PATH"
  '
)"
assert_contains "interactive-still-contains-npm-global" "$INTERACTIVE_PATH" "/home/agentdev/.npm-global/bin"

# --- Test 4: command -v claude resolves to npm-global/bin after the PATH export fires ---
# CM-2 fix: do NOT rewrite the full acorn script via sed (brittle, false-positive risk).
# Instead, create a minimal stub that contains ONLY the PATH export line under test,
# then verify command -v resolves correctly. This tests the mechanism in isolation.
MOCK_NPM_GLOBAL="$TMPDIR_BASE/.npm-global/bin"
mkdir -p "$MOCK_NPM_GLOBAL"
printf '#!/usr/bin/env bash\nexit 0\n' > "$MOCK_NPM_GLOBAL/claude"
chmod +x "$MOCK_NPM_GLOBAL/claude"

# Extract only the export PATH line from the production script (no full-script rewrite)
EXPORT_LINE=$(grep -E '^export PATH=' "$ACORN_SCRIPT" | head -1)
# Build a minimal 3-line stub: set -euo, the export line (with mock path substituted), done
TMP_STUB="$TMPDIR_BASE/path_stub.sh"
printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' \
  "${EXPORT_LINE/\/home\/agentdev\/.npm-global\/bin/$MOCK_NPM_GLOBAL}" > "$TMP_STUB"

CMD_RESULT="$(
  env -i HOME="$REAL_HOME" PATH="/usr/bin:/bin" bash -c '
    set -euo pipefail
    source "'"$TMP_STUB"'"
    command -v claude
  '
)"
assert_eq "command-v-claude-resolves" "$CMD_RESULT" "$MOCK_NPM_GLOBAL/claude"

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
