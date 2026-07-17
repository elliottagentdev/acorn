#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'

# test_resolve_issue_number.sh -- G1 tests for resolve_issue_number (forge-841)
#   (a)/(a2) numbered-slug regression guard + precedence
#   (b)      issue-less slug + meta.json fallback
#   (c..c5)  negative controls: no field / 0 / no file / malformed / fractional-float / negative / non-numeric-string
#   (c5a)/(a1) jq-canonicalized integer inputs ACCEPTED: float 67.0 -> 67, string "67" -> 67
#   (b-real)/(c-real) real cmd_approve caller: positive fallback + negative die contract

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACORN_SCRIPT="${ACORN_SCRIPT:-$SCRIPT_DIR/bin/acorn}"
[ -f "$ACORN_SCRIPT" ] || { echo "ACORN_SCRIPT not found: $ACORN_SCRIPT" >&2; exit 1; }
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }
assert_eq() { local n="$1" a="$2" e="$3"; [ "$a" = "$e" ] && pass "$n" || fail "$n" "expected '$e', got '$a'"; }

TMP="$(mktemp -d)"
REAL_TMPS=()
cleanup_all() {
  rm -rf "$TMP" "${REAL_TMPS[@]}" 2>/dev/null || true
  rm -f "$TMP/acorn_841_cneg_err" "$TMP/acorn_841_bpos_capture" 2>/dev/null || true
}
trap cleanup_all EXIT

test_a_numbered_slug() {
  local r
  r="$(resolve_issue_number "66-foo-bar" "$TMP/does-not-exist")"
  assert_eq "a: numbered slug -> 66 (no fallback)" "$r" "66"
}

test_a2_numbered_slug_meta_ignored() {
  local sd="$TMP/66-with-meta"
  mkdir -p "$sd"
  printf '{"issue_number": 999, "slug": "66-with-meta"}\n' > "$sd/meta.json"
  local r
  r="$(resolve_issue_number "66-with-meta" "$sd")"
  assert_eq "a2: slug wins over meta" "$r" "66"
}

test_b_issueless_with_meta() {
  local sd="$TMP/issueless-spec"
  mkdir -p "$sd"
  printf '{"issue_number": 67, "slug": "issueless-spec"}\n' > "$sd/meta.json"
  local r
  r="$(resolve_issue_number "issueless-spec" "$sd")"
  assert_eq "b: meta.json fallback -> 67" "$r" "67"
}

test_c_issueless_no_meta_field() {
  local sd="$TMP/no-num-spec"
  mkdir -p "$sd"
  printf '{"slug": "no-num-spec"}\n' > "$sd/meta.json"
  local r
  r="$(resolve_issue_number "no-num-spec" "$sd")"
  assert_eq "c: no issue_number field -> empty" "$r" ""
}

test_c2_issueless_zero() {
  local sd="$TMP/zero-spec"
  mkdir -p "$sd"
  printf '{"issue_number": 0, "slug": "zero-spec"}\n' > "$sd/meta.json"
  local r
  r="$(resolve_issue_number "zero-spec" "$sd")"
  assert_eq "c2: issue_number 0 -> empty" "$r" ""
}

test_c3_issueless_no_metafile() {
  local sd="$TMP/absent-spec"
  mkdir -p "$sd"
  local r
  r="$(resolve_issue_number "absent-spec" "$sd")"
  assert_eq "c3: no meta.json -> empty" "$r" ""
}

test_c4_malformed_meta() {
  local sd="$TMP/bad-spec"
  mkdir -p "$sd"
  printf 'not json {{{\n' > "$sd/meta.json"
  local r
  r="$(resolve_issue_number "bad-spec" "$sd")"
  assert_eq "c4: malformed meta.json -> empty" "$r" ""
}

test_c5a_integer_float_accepted() {
  local sd="$TMP/intfloat-spec"
  mkdir -p "$sd"
  printf '{"issue_number": 67.0, "slug": "intfloat-spec"}\n' > "$sd/meta.json"
  local r
  r="$(resolve_issue_number "intfloat-spec" "$sd")"
  assert_eq "c5a: integer-valued float 67.0 -> 67 (accepted)" "$r" "67"
}

test_a1_numeric_string_accepted() {
  local sd="$TMP/numstr-spec"
  mkdir -p "$sd"
  printf '{"issue_number": "67", "slug": "numstr-spec"}\n' > "$sd/meta.json"
  local r
  r="$(resolve_issue_number "numstr-spec" "$sd")"
  assert_eq "a1: numeric string \"67\" -> 67 (accepted)" "$r" "67"
}

test_c5a2_fractional_float() {
  local sd="$TMP/fracfloat-spec"
  mkdir -p "$sd"
  printf '{"issue_number": 67.5, "slug": "fracfloat-spec"}\n' > "$sd/meta.json"
  local r
  r="$(resolve_issue_number "fracfloat-spec" "$sd")"
  assert_eq "c5a2: fractional float 67.5 -> empty" "$r" ""
}

test_c5b_negative_issue_number() {
  local sd="$TMP/neg-spec"
  mkdir -p "$sd"
  printf '{"issue_number": -5, "slug": "neg-spec"}\n' > "$sd/meta.json"
  local r
  r="$(resolve_issue_number "neg-spec" "$sd")"
  assert_eq "c5b: negative issue_number -> empty" "$r" ""
}

test_c5c_nonnumeric_string_issue_number() {
  local sd="$TMP/str-spec"
  mkdir -p "$sd"
  printf '{"issue_number": "abc", "slug": "str-spec"}\n' > "$sd/meta.json"
  local r
  r="$(resolve_issue_number "str-spec" "$sd")"
  assert_eq "c5c: non-numeric string issue_number -> empty" "$r" ""
}

test_b_real_cmd_approve_meta_fallback() {
  local d
  d="$(mktemp -d)"
  REAL_TMPS+=("$d")
  (
    cd "$d"
    git init -q
    git config user.email t@e.com
    git config user.name t
  )

  mkdir -p "$d/.specs/wi-issueless/plans"
  printf '# spec\n' > "$d/.specs/wi-issueless/plans/SPEC.md"
  printf '{"issue_number":8675,"slug":"wi-issueless","output_mode":"single"}\n' > "$d/.specs/wi-issueless/meta.json"

  safe_repo_main() { printf '%s' "$d"; }
  spec_dir() { printf '%s/.specs/%s' "$d" "$2"; }
  require_cmds() { :; }
  local captured_file="$TMP/acorn_841_bpos_capture"
  : > "$captured_file"
  set_issue_state_label() { printf '%s' "$2" > "$captured_file"; }
  comment_issue() { :; }
  notify_telegram() { :; }
  notify_foreman() { :; }

  FOREMAN_HOME=/nonexistent cmd_approve "fake-repo" "wi-issueless" --no-commit >/dev/null

  local captured
  captured="$(<"$captured_file")"
  assert_eq "b-real: cmd_approve used meta issue_number" "$captured" "8675"

  unset -f safe_repo_main spec_dir require_cmds set_issue_state_label comment_issue notify_telegram notify_foreman
}

test_c_real_cmd_approve_dies() {
  local d
  d="$(mktemp -d)"
  REAL_TMPS+=("$d")
  (
    cd "$d"
    git init -q
    git config user.email t@e.com
    git config user.name t
  )

  mkdir -p "$d/.specs/no-issue-slug/plans"
  printf '# spec\n' > "$d/.specs/no-issue-slug/plans/SPEC.md"
  printf '{"slug":"no-issue-slug"}\n' > "$d/.specs/no-issue-slug/meta.json"

  safe_repo_main() { printf '%s' "$d"; }
  spec_dir() { printf '%s/.specs/%s' "$d" "$2"; }
  require_cmds() { :; }
  set_issue_state_label() { :; }
  comment_issue() { :; }
  notify_telegram() { :; }
  notify_foreman() { :; }
  export -f safe_repo_main spec_dir require_cmds set_issue_state_label \
    comment_issue notify_telegram notify_foreman

  local err_file="$TMP/acorn_841_cneg_err"
  local rc=0
  ( FOREMAN_HOME=/nonexistent cmd_approve "fake-repo" "no-issue-slug" --no-commit ) \
    2>"$err_file" >/dev/null || rc=$?

  if [ "$rc" -ne 0 ] && grep -q "Cannot infer issue number" "$err_file"; then
    pass "c-real: cmd_approve dies with unchanged message on issue-less slug"
  else
    fail "c-real: cmd_approve die contract" "rc=$rc"
  fi

  unset -f safe_repo_main spec_dir require_cmds set_issue_state_label \
    comment_issue notify_telegram notify_foreman
}

test_a_numbered_slug
test_a2_numbered_slug_meta_ignored
test_b_issueless_with_meta
test_c_issueless_no_meta_field
test_c2_issueless_zero
test_c3_issueless_no_metafile
test_c4_malformed_meta
test_c5a_integer_float_accepted
test_a1_numeric_string_accepted
test_c5a2_fractional_float
test_c5b_negative_issue_number
test_c5c_nonnumeric_string_issue_number
test_b_real_cmd_approve_meta_fallback
test_c_real_cmd_approve_dies

printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
