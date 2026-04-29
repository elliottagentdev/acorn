#!/usr/bin/env bash
set -euo pipefail

ACORN_SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/bin/acorn"
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }

assert_eq() {
  local name="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then pass "$name"; else fail "$name" "expected '$expected', got '$actual'"; fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then pass "$name"; else fail "$name" "expected to contain '$needle'"; fi
}

TMPDIR_BASE="$(mktemp -d)"

setup() {
  CURL_LOG="$TMPDIR_BASE/curl_calls.log"
  : > "$CURL_LOG"
}

teardown() {
  rm -rf "$TMPDIR_BASE"
  unset -f curl 2>/dev/null || true
}

# Mock curl to capture calls instead of making HTTP requests
curl() {
  printf '%s\n' "$*" >> "$CURL_LOG"
  return 0
}
export -f curl
export CURL_LOG

# Also export TELEGRAM_NOTIFY_URL so notify_telegram can see it
export TELEGRAM_NOTIFY_URL

# --- Test 1: message-only payload uses correct JSON ---
printf '\n\033[1mTest: notify_telegram message-only payload\033[0m\n'
setup
notify_telegram "spec pipeline started for #42"
sleep 1  # wait for background subshell
wait 2>/dev/null || true
if [ -s "$CURL_LOG" ]; then
  log_content="$(cat "$CURL_LOG")"
  assert_contains "curl called" "$log_content" "Content-Type: application/json"
  assert_contains "message in payload" "$log_content" "spec pipeline started for #42"
  assert_contains "targets notify URL" "$log_content" "/notify"
else
  fail "curl called" "curl was not called (log empty)"
fi

# --- Test 2: message+session payload ---
printf '\n\033[1mTest: notify_telegram message+session payload\033[0m\n'
setup
notify_telegram "test msg" "forge-main-pi"
sleep 1
wait 2>/dev/null || true
if [ -s "$CURL_LOG" ]; then
  log_content="$(cat "$CURL_LOG")"
  assert_contains "session in payload" "$log_content" "forge-main-pi"
  assert_contains "message in payload" "$log_content" "test msg"
else
  fail "curl called with session" "curl was not called (log empty)"
fi

# --- Test 3: curl failure does not propagate ---
printf '\n\033[1mTest: notify_telegram handles curl failure silently\033[0m\n'
curl() { return 1; }
export -f curl
notify_telegram "should not fail"
sleep 1
wait 2>/dev/null || true
pass "silent failure (no crash)"

# --- Test 4: missing curl does not crash ---
printf '\n\033[1mTest: notify_telegram handles missing curl\033[0m\n'
unset -f curl
# Temporarily hide curl from PATH. Pre-resolve sleep since PATH will be broken.
SLEEP_BIN="$(command -v sleep)"
OLD_PATH="$PATH"
export PATH="/usr/bin/doesnotexist"
notify_telegram "no curl available"
"$SLEEP_BIN" 1
wait 2>/dev/null || true
export PATH="$OLD_PATH"
pass "missing curl handled (no crash)"

teardown

printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
