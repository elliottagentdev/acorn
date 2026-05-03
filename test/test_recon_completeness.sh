#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACORN_SCRIPT="$SCRIPT_DIR/bin/acorn"
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"

PASS=0; FAIL=0
pass(){ PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail(){ FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }
assert_contains(){ local n="$1" h="$2" needle="$3"; printf '%s' "$h" | grep -qF -- "$needle" && pass "$n" || fail "$n" "missing $needle"; }
assert_eq(){ [ "$2" = "$3" ] && pass "$1" || fail "$1" "expected '$3' got '$2'"; }

notify_telegram(){ :; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

test_validate_stage(){
  local sd="$TMP/spec"; mkdir -p "$sd/recon"
  printf '## Directory Structure\nX\n' > "$sd/recon/architecture.md"
  printf '## A\n' > "$sd/recon/relevant_code.md"
  : > "$sd/recon/conventions.md"
  set +e
  local err; err="$(validate_stage_artifacts "$sd" lite 0 2>&1)"; local rc=$?
  set -e
  assert_eq "validate stage fails on empty" "$rc" "1"
  assert_contains "validate shows EMPTY" "$err" "EMPTY|recon/conventions.md"
}

test_internal_halt_event(){
  local pd="$TMP/projects"; mkdir -p "$pd/repo/main/.specs/slug/recon"
  PROJECTS_DIR="$pd"
  local sd="$pd/repo/main/.specs/slug"
  cat > "$sd/meta.json" <<EOF
{"repo":"repo","issue_number":2,"slug":"slug","session_name":"sess"}
EOF
  local evt="$TMP/events.jsonl"; ACORN_FAILURE_EVENT_PATH="$evt"
  set +e
  acorn_halt_out="$(cmd_internal halt "$sd" lite 0 "Agent A" "recon/architecture.md" artifact_missing "file missing" 2>&1)"; rc=$?
  set -e
  assert_eq "halt returns non-zero" "$rc" "1"
  [ -f "$sd/recon/HALT.md" ] && pass "halt file written" || fail "halt file written" "missing"
  [ -s "$evt" ] && pass "event written" || fail "event written" "missing"
  assert_contains "stderr has Pipeline halted" "$acorn_halt_out" "Pipeline halted"
}

test_status_prefix(){
  local sd="$TMP/status"; mkdir -p "$sd/recon" "$sd/plans"
  : > "$sd/recon/HALT.md"; : > "$sd/PROMPT.md"
  gh(){ return 1; }
  local st; st="$(status_for_spec "$TMP" "" "$sd")"
  assert_contains "status prefixed" "$st" "[HALTED]"
}

test_validate_prompt_placeholders(){
  local f="$TMP/prompt.md"
  cat > "$f" <<EOF
## PLANNING METHODOLOGY — MANDATORY INSTRUCTIONS
__MODE__
EOF
  set +e
  validate_prompt_md "$f"; local rc=$?
  set -e
  assert_eq "placeholder lint fails" "$rc" "1"
}

test_validate_stage
test_internal_halt_event
test_status_prefix
test_validate_prompt_placeholders

printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
