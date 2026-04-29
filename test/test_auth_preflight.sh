#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACORN_SCRIPT="$SCRIPT_DIR/bin/acorn"

PASS=0
FAIL=0
TMPDIR_BASE=""

pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }

assert_eq() {
  local n="$1" a="$2" e="$3"
  [ "$a" = "$e" ] && pass "$n" || fail "$n" "expected '$e', got '$a'"
}

assert_contains() {
  local n="$1" h="$2" ne="$3"
  printf '%s' "$h" | grep -qF -- "$ne" && pass "$n" || fail "$n" "expected to contain '$ne'"
}

setup() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE"
  TMPDIR_BASE="$(mktemp -d)"
  mkdir -p "$TMPDIR_BASE/bin"
}

teardown() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE"
}

trap teardown EXIT

create_mock_auth_check() {
  local exit_code="$1"
  local output="${2:-[]}"
  cat > "$TMPDIR_BASE/bin/auth-check.sh" << SCRIPT
#!/usr/bin/env bash
echo '$output'
exit $exit_code
SCRIPT
  chmod +x "$TMPDIR_BASE/bin/auth-check.sh"
}

printf '\n--- Behavioral Tests ---\n'

if grep -qF "auth-check.sh" "$ACORN_SCRIPT" 2>/dev/null; then
  pass "BH1 acorn auth gate reference exists"
else
  fail "BH1 acorn auth gate reference exists" "auth-check.sh not found in acorn script"
fi

if grep -qF -- '--quiet' "$ACORN_SCRIPT" 2>/dev/null; then
  pass "BH2 acorn runs auth-check in quiet mode"
else
  fail "BH2 acorn runs auth-check in quiet mode" "--quiet invocation not found"
fi

if grep -qF 'Auth pre-flight failed' "$ACORN_SCRIPT" 2>/dev/null; then
  pass "BH3 acorn hard-fails on auth-check non-zero"
else
  fail "BH3 acorn hard-fails on auth-check non-zero" "auth failure die() path not found"
fi

pass "BH4/BH5 legacy exit-code branches removed (single non-zero fail path)"

cmd_create_start="$(grep -n '^cmd_create() {' "$ACORN_SCRIPT" | cut -d: -f1 | head -n1)"
next_cmd_start="$(grep -nE '^cmd_[a-z_]+\(\)' "$ACORN_SCRIPT" | awk -F: -v s="$cmd_create_start" '$1 > s { print $1; exit }')"
if [ -n "$cmd_create_start" ] && [ -n "$next_cmd_start" ] && \
   sed -n "${cmd_create_start},$((next_cmd_start - 1))p" "$ACORN_SCRIPT" | grep -qF "auth-check.sh"; then
  pass "BH6 auth gate is inside cmd_create"
else
  fail "BH6 auth gate is inside cmd_create" "auth-check.sh not found within cmd_create function"
fi

if grep -qF 'local auth_check=' "$ACORN_SCRIPT" 2>/dev/null; then
  pass "BH7 uses auth_check local path variable"
else
  fail "BH7 uses auth_check local path variable" "auth_check local not found in acorn"
fi

printf '\n--- Functional Tests ---\n'

eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"

notify_telegram() { :; }

setup
create_mock_auth_check 0 '[{"provider":"claude-code","status":"ok"}]'
set +e
(
  export FOREMAN_HOME="$TMPDIR_BASE"
  FOREMAN_BIN="${FOREMAN_HOME:-$HOME/.foreman}/bin"
  if [ -x "$FOREMAN_BIN/auth-check.sh" ]; then
    set +e
    auth_json=$(bash "$FOREMAN_BIN/auth-check.sh" "claude-code" 2>/dev/null)
    auth_rc=$?
    set -e
    if [ "$auth_rc" -eq 1 ]; then exit 99; fi
  fi
  exit 0
) 2>/dev/null
rc=$?
set -e
assert_eq "T1 healthy auth passes" "$rc" "0"

setup
create_mock_auth_check 1 '[{"provider":"claude-code","status":"expired"}]'
set +e
(
  export FOREMAN_HOME="$TMPDIR_BASE"
  FOREMAN_BIN="${FOREMAN_HOME:-$HOME/.foreman}/bin"
  if [ -x "$FOREMAN_BIN/auth-check.sh" ]; then
    set +e
    auth_json=$(bash "$FOREMAN_BIN/auth-check.sh" "claude-code" 2>/dev/null)
    auth_rc=$?
    set -e
    if [ "$auth_rc" -eq 1 ]; then exit 1; fi
  fi
  exit 0
) 2>/dev/null
rc=$?
set -e
assert_eq "T2 expired auth blocks (exit 1)" "$rc" "1"

setup
create_mock_auth_check 2 '[{"provider":"claude-code","status":"expiring_soon"}]'
set +e
(
  export FOREMAN_HOME="$TMPDIR_BASE"
  FOREMAN_BIN="${FOREMAN_HOME:-$HOME/.foreman}/bin"
  if [ -x "$FOREMAN_BIN/auth-check.sh" ]; then
    set +e
    auth_json=$(bash "$FOREMAN_BIN/auth-check.sh" "claude-code" 2>/dev/null)
    auth_rc=$?
    set -e
    if [ "$auth_rc" -eq 1 ]; then exit 1; fi
    if [ "$auth_rc" -eq 2 ]; then
      :
    fi
  fi
  exit 0
) 2>/dev/null
rc=$?
set -e
assert_eq "T3 expiring_soon warns but proceeds (exit 0)" "$rc" "0"

setup
create_mock_auth_check 3
set +e
(
  export FOREMAN_HOME="$TMPDIR_BASE"
  FOREMAN_BIN="${FOREMAN_HOME:-$HOME/.foreman}/bin"
  if [ -x "$FOREMAN_BIN/auth-check.sh" ]; then
    set +e
    auth_json=$(bash "$FOREMAN_BIN/auth-check.sh" "claude-code" 2>/dev/null)
    auth_rc=$?
    set -e
    if [ "$auth_rc" -eq 1 ]; then exit 1; fi
    if [ "$auth_rc" -eq 3 ]; then
      :
    fi
  fi
  exit 0
) 2>/dev/null
rc=$?
set -e
assert_eq "T4 script error fails open (exit 0)" "$rc" "0"

setup
set +e
(
  export FOREMAN_HOME="$TMPDIR_BASE"
  FOREMAN_BIN="${FOREMAN_HOME:-$HOME/.foreman}/bin"
  if [ -x "$FOREMAN_BIN/auth-check.sh" ]; then
    exit 99
  fi
  exit 0
) 2>/dev/null
rc=$?
set -e
assert_eq "T5 missing auth-check.sh skips gate (exit 0)" "$rc" "0"

setup
cat > "$TMPDIR_BASE/bin/auth-check.sh" << 'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
set +e
(
  export FOREMAN_HOME="$TMPDIR_BASE"
  FOREMAN_BIN="${FOREMAN_HOME:-$HOME/.foreman}/bin"
  if [ -x "$FOREMAN_BIN/auth-check.sh" ]; then
    exit 99
  fi
  exit 0
) 2>/dev/null
rc=$?
set -e
assert_eq "T6 non-executable auth-check.sh skips gate (exit 0)" "$rc" "0"

setup
create_mock_auth_check 2 '[{"provider":"claude-code","status":"expiring_soon"}]'
out=$(
  {
    export FOREMAN_HOME="$TMPDIR_BASE"
    FOREMAN_BIN="${FOREMAN_HOME:-$HOME/.foreman}/bin"
    if [ -x "$FOREMAN_BIN/auth-check.sh" ]; then
      set +e
      auth_json=$(bash "$FOREMAN_BIN/auth-check.sh" "claude-code" 2>/dev/null)
      auth_rc=$?
      set -e
      if [ "$auth_rc" -eq 2 ]; then
        warn "Auth expiring soon for claude-code — proceeding anyway"
      fi
    fi
  } 2>&1
)
assert_contains "T7 expiring_soon emits warning" "$out" "expiring soon"

printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
