#!/usr/bin/env bash
set -euo pipefail
ACORN_SCRIPT="${ACORN_BIN:-/home/agentdev/acorn/bin/acorn}"
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"

PASS=0; FAIL=0
pass(){ PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail(){ FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }

ACORN_CLARIFY_ENABLED=0
OUT="$(auto_trigger_message '/tmp/x' 'lite')"
case "$OUT" in
  *"clarify pre-Stage-0"*) fail "off-mode" "should NOT mention clarify when disabled" ;;
  *) pass "off-mode" ;;
esac

ACORN_CLARIFY_ENABLED=1
OUT="$(auto_trigger_message '/tmp/x' 'lite')"
case "$OUT" in
  *"clarify pre-Stage-0"*) pass "on-mode" ;;
  *) fail "on-mode" "should mention clarify when enabled" ;;
esac

[ "$FAIL" -eq 0 ] || exit 1
