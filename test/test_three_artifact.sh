#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACORN_SCRIPT="$SCRIPT_DIR/bin/acorn"
unset ACORN_OUTPUT_MODE
# shellcheck disable=SC1090
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"

PASS=0; FAIL=0
pass(){ PASS=$((PASS+1)); echo "PASS $1"; }
fail(){ FAIL=$((FAIL+1)); echo "FAIL $1 -- $2"; }
assert_contains(){ local n="$1" h="$2" k="$3"; printf '%s' "$h" | grep -qF -- "$k" && pass "$n" || fail "$n" "missing $k"; }
assert_not_contains(){ local n="$1" h="$2" k="$3"; printf '%s' "$h" | grep -qF -- "$k" && fail "$n" "unexpected $k" || pass "$n"; }
assert_eq(){ local n="$1" a="$2" e="$3"; [ "$a" = "$e" ] && pass "$n" || fail "$n" "expected $e got $a"; }

TMP=""
setup(){ TMP="$(mktemp -d)"; }
teardown(){ [ -n "$TMP" ] && rm -rf "$TMP"; unset -f safe_repo_main spec_dir ensure_labels set_issue_state_label comment_issue notify_telegram notify_foreman register_with_forged check_circuit_breaker gh extract_and_download_images start_session send_auto_trigger 2>/dev/null || true; }
trap teardown EXIT

mock_common(){
  safe_repo_main(){ printf '%s' "$TMP/repo"; }
  spec_dir(){ printf '%s' "$TMP/spec"; }
  ensure_labels(){ :; }
  set_issue_state_label(){ :; }
  comment_issue(){ :; }
  notify_telegram(){ :; }
  notify_foreman(){ :; }
  register_with_forged(){ :; }
  check_circuit_breaker(){ return 0; }
  gh(){
    if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
      printf '{"title":"t","body":"b","comments":[]}'
    else
      printf '{}'
    fi
  }
  extract_and_download_images(){ : > "$TMP/map"; printf '%s' "$TMP/map"; }
  start_session(){ printf 's\n'; }
  send_auto_trigger(){ :; }
  export -f safe_repo_main spec_dir ensure_labels set_issue_state_label comment_issue notify_telegram notify_foreman register_with_forged check_circuit_breaker gh extract_and_download_images start_session send_auto_trigger
  mkdir -p "$TMP/repo" "$TMP/spec/plans" "$TMP/spec/recon" "$TMP/spec/images"
}

setup
out="$(render_prompt_md "t" "b" '{"comments":[]}' "$TMP/o" lite /tmp/spec '' three-artifact; cat "$TMP/o")"
assert_contains "prompt has block" "$out" "THREE-ARTIFACT OUTPUT MODE"
assert_contains "prompt has schema marker" "$out" "acorn-tasks-schema: v1"

setup
meta="$TMP/meta.json"
write_meta_json "$meta" r 1 t s tmux sess lite three-artifact
assert_eq "meta output_mode" "$(jq -r '.output_mode' "$meta")" "three-artifact"

setup
MOCK_SPEC="$TMP/spec"; mkdir -p "$MOCK_SPEC/plans"; echo x > "$MOCK_SPEC/plans/SPEC.md"
write_meta_json "$MOCK_SPEC/meta.json" r 1 t s tmux sess lite three-artifact
spec_dir(){ printf '%s' "$MOCK_SPEC"; }; export -f spec_dir
safe_repo_main(){ printf '%s' "$TMP/repo"; }; export -f safe_repo_main
ensure_labels(){ :; }; set_issue_state_label(){ :; }; comment_issue(){ :; }; notify_telegram(){ :; }
export -f ensure_labels set_issue_state_label comment_issue notify_telegram
stderr="$TMP/e"; cmd_approve r 1-s 2>"$stderr" >/dev/null || true
assert_contains "approve warns plan" "$(cat "$stderr")" "missing or empty PLAN.md"

printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
