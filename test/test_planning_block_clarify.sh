#!/usr/bin/env bash
set -euo pipefail
ACORN_SCRIPT="${ACORN_BIN:-/home/agentdev/acorn/bin/acorn}"
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"

PASS=0; FAIL=0
pass(){ PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail(){ FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }

OUT="$(planning_block_clarify '/tmp/test-spec' 'lite')"

case "$OUT" in
  *"__SPEC_PATH__"*) fail "spec_path-sub" "found unsubstituted __SPEC_PATH__" ;;
  *"__MODE__"*)      fail "mode-sub" "found unsubstituted __MODE__" ;;
  *"/tmp/test-spec"*) pass "spec_path-sub" ;;
esac

case "$OUT" in
  *"acorn _internal validate-stage \"/tmp/test-spec\" lite pre0"*) pass "validate-stage-line" ;;
  *) fail "validate-stage-line" "missing or wrong" ;;
esac

[ "$FAIL" -eq 0 ] || exit 1
