#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACORN_SCRIPT="$SCRIPT_DIR/bin/acorn"

# Source acorn functions without triggering main()
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"

PASS=0
FAIL=0
TMPDIR_BASE=""

pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }

assert_eq() {
  local name="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$name"
  else
    fail "$name" "expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    pass "$name"
  else
    fail "$name" "expected to contain '$needle'"
  fi
}

assert_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    fail "$name" "expected NOT to contain '$needle'"
  else
    pass "$name"
  fi
}

setup() {
  TMPDIR_BASE="$(mktemp -d)"
}

teardown() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE"
  unset -f claude 2>/dev/null || true
  unset -f gh_issue_json 2>/dev/null || true
  unset -f safe_repo_main 2>/dev/null || true
  unset -f require_cmds 2>/dev/null || true
  unset -f analyze_issue_for_split 2>/dev/null || true
  unset -f create_issue_in_repo 2>/dev/null || true
  unset -f comment_issue 2>/dev/null || true
}

# ──────────────────────────────────────
# T1: complexity_band boundaries
# ──────────────────────────────────────
test_complexity_band_boundaries() {
  printf '\n\033[1m== T1: complexity_band boundaries ==\033[0m\n'

  assert_eq "5->LOW"  "$(complexity_band 5)"  "LOW"
  assert_eq "7->LOW"  "$(complexity_band 7)"  "LOW"
  assert_eq "8->MED"  "$(complexity_band 8)"  "MED"
  assert_eq "11->MED" "$(complexity_band 11)" "MED"
  assert_eq "12->HIGH" "$(complexity_band 12)" "HIGH"
  assert_eq "15->HIGH" "$(complexity_band 15)" "HIGH"
}

# ──────────────────────────────────────
# T2: complexity_band config override
# ──────────────────────────────────────
test_complexity_band_config_override() {
  printf '\n\033[1m== T2: complexity_band config override ==\033[0m\n'

  assert_eq "4->MED (override)"  "$(ACORN_COMPLEXITY_LOW_MAX=3 ACORN_COMPLEXITY_MED_MAX=6 complexity_band 4)"  "MED"
  assert_eq "7->HIGH (override)" "$(ACORN_COMPLEXITY_LOW_MAX=3 ACORN_COMPLEXITY_MED_MAX=6 complexity_band 7)"  "HIGH"
}

# ──────────────────────────────────────
# T3: complexity_band non-numeric
# ──────────────────────────────────────
test_complexity_band_non_numeric() {
  printf '\n\033[1m== T3: complexity_band non-numeric ==\033[0m\n'

  assert_eq "foo->UNKNOWN" "$(complexity_band foo)" "UNKNOWN"
  assert_eq "empty->UNKNOWN" "$(complexity_band '')" "UNKNOWN"
}

# ──────────────────────────────────────
# T4: check_size_thresholds LOC gate
# ──────────────────────────────────────
test_check_size_thresholds_loc() {
  printf '\n\033[1m== T4: check_size_thresholds LOC gate ==\033[0m\n'

  assert_eq "800,0->false" "$(check_size_thresholds 800 0)" "false"
  assert_eq "801,0->true"  "$(check_size_thresholds 801 0)" "true"
}

# ──────────────────────────────────────
# T5: check_size_thresholds files gate
# ──────────────────────────────────────
test_check_size_thresholds_files() {
  printf '\n\033[1m== T5: check_size_thresholds files gate ==\033[0m\n'

  assert_eq "0,8->false" "$(check_size_thresholds 0 8)" "false"
  assert_eq "0,9->true"  "$(check_size_thresholds 0 9)" "true"
}

# ──────────────────────────────────────
# T6: check_size_thresholds config override
# ──────────────────────────────────────
test_check_size_thresholds_config_override() {
  printf '\n\033[1m== T6: check_size_thresholds config override ==\033[0m\n'

  local result
  result="$(ACORN_LOC_DECOMP_THRESHOLD=100 check_size_thresholds 101 0)"
  assert_eq "101,0->true (override)" "$result" "true"
}

# ──────────────────────────────────────
# T7: enrich_complexity computes band
# ──────────────────────────────────────
test_enrich_complexity_computes_band() {
  printf '\n\033[1m== T7: enrich_complexity computes band ==\033[0m\n'

  local dims='{
    "should_split": false,
    "reasoning": "test",
    "sub_issues": [],
    "complexity": {
      "dims": {
        "files_touched": 3,
        "loc_estimate": 3,
        "novelty": 3,
        "context_depth": 2,
        "cross_module_fan_out": 2
      },
      "loc_estimate_total": 100,
      "files_estimate_total": 2,
      "atomic_justification": null
    }
  }'

  local result
  result="$(enrich_complexity "$dims")"

  local band score decomp
  band="$(printf '%s' "$result" | jq -r '.complexity.band')"
  score="$(printf '%s' "$result" | jq -r '.complexity.score')"
  decomp="$(printf '%s' "$result" | jq -r '.complexity.decomposition_required')"

  assert_eq "band=HIGH" "$band" "HIGH"
  assert_eq "score=13" "$score" "13"
  assert_eq "decomposition_required=true" "$decomp" "true"
}

# ──────────────────────────────────────
# T8: enrich_complexity size flag independent of band
# ──────────────────────────────────────
test_enrich_complexity_size_independent_of_band() {
  printf '\n\033[1m== T8: enrich_complexity size flag independent of band ==\033[0m\n'

  local dims='{
    "should_split": false,
    "reasoning": "test",
    "sub_issues": [],
    "complexity": {
      "dims": {
        "files_touched": 1,
        "loc_estimate": 1,
        "novelty": 2,
        "context_depth": 1,
        "cross_module_fan_out": 1
      },
      "loc_estimate_total": 950,
      "files_estimate_total": 2,
      "atomic_justification": null
    }
  }'

  local result
  result="$(enrich_complexity "$dims")"

  local band review decomp
  band="$(printf '%s' "$result" | jq -r '.complexity.band')"
  review="$(printf '%s' "$result" | jq -r '.complexity.size_flag.decomposition_review_required')"
  decomp="$(printf '%s' "$result" | jq -r '.complexity.decomposition_required')"

  assert_eq "band=LOW (sum=6)" "$band" "LOW"
  assert_eq "size_flag=true (950>800)" "$review" "true"
  assert_eq "decomposition_required=false (band=LOW)" "$decomp" "false"
}

# ──────────────────────────────────────
# T9: enrich_complexity legacy pass-through
# ──────────────────────────────────────
test_enrich_complexity_legacy_pass_through() {
  printf '\n\033[1m== T9: enrich_complexity legacy pass-through ==\033[0m\n'

  local legacy='{"should_split":true,"reasoning":"test","sub_issues":[{"title":"A","scope":"scope A"}]}'
  local result
  result="$(enrich_complexity "$legacy")"

  # Must be byte-identical (no .complexity key added)
  assert_eq "legacy pass-through unchanged" "$result" "$legacy"
  # Must still have 3 required keys
  local has_keys
  has_keys="$(printf '%s' "$result" | jq 'has("should_split") and has("reasoning") and has("sub_issues")')"
  assert_eq "legacy has 3 keys" "$has_keys" "true"
  # Must NOT have complexity key
  if printf '%s' "$result" | jq -e '.complexity' >/dev/null 2>&1; then
    fail "legacy has no .complexity key" "unexpected .complexity key present"
  else
    pass "legacy has no .complexity key"
  fi
}

# ──────────────────────────────────────
# T10: analyze_issue_for_split extended (complexity block returned)
# ──────────────────────────────────────
test_analyze_extended_complexity() {
  printf '\n\033[1m== T10: analyze_issue_for_split extended ==\033[0m\n'

  claude() {
    cat <<'MOCK_EOF'
{"should_split":true,"reasoning":"test reason","sub_issues":[{"title":"A","scope":"scope A"}],"complexity":{"dims":{"files_touched":1,"loc_estimate":1,"novelty":1,"context_depth":1,"cross_module_fan_out":1},"loc_estimate_total":200,"files_estimate_total":3,"atomic_justification":null}}
MOCK_EOF
  }
  export -f claude

  local result
  result="$(analyze_issue_for_split "Test title" "Test body" "" "mock" 2>/dev/null)"

  local should_split band score
  should_split="$(printf '%s' "$result" | jq -r '.should_split')"
  band="$(printf '%s' "$result" | jq -r '.complexity.band // "missing"')"
  score="$(printf '%s' "$result" | jq -r '.complexity.score // "missing"')"

  assert_eq "parses should_split" "$should_split" "true"
  assert_eq "has band" "$band" "LOW"
  assert_eq "has score=5" "$score" "5"
  # Must still validate 3-key contract
  if printf '%s' "$result" | jq -e 'has("should_split") and has("reasoning") and has("sub_issues")' >/dev/null 2>&1; then
    pass "validates 3-key contract"
  else
    fail "validates 3-key contract" "missing one of should_split/reasoning/sub_issues"
  fi

  unset -f claude
}

# ──────────────────────────────────────
# T11: analyze_issue_for_split backward-compat (legacy 3-key)
# ──────────────────────────────────────
test_analyze_backward_compat() {
  printf '\n\033[1m== T11: analyze_issue_for_split backward-compat ==\033[0m\n'

  claude() {
    echo '{"should_split":false,"reasoning":"focused issue","sub_issues":[]}'
  }
  export -f claude

  local result
  result="$(analyze_issue_for_split "Test" "Body" "" "mock" 2>/dev/null)"

  local should_split
  should_split="$(printf '%s' "$result" | jq -r '.should_split')"
  assert_eq "backward-compat should_split=false" "$should_split" "false"

  # Must validate 3-key contract
  if printf '%s' "$result" | jq -e 'has("should_split") and has("reasoning") and has("sub_issues")' >/dev/null 2>&1; then
    pass "backward-compat validates 3-key"
  else
    fail "backward-compat validates 3-key" "missing keys"
  fi

  # Must NOT crash
  pass "backward-compat no crash"

  unset -f claude
}

# ──────────────────────────────────────
# T12+T13 paired: cmd_issue_split HIGH surfacing vs LOW silence
# ──────────────────────────────────────
test_cmd_split_high_surfacing_paired() {
  printf '\n\033[1m== T12+T13: cmd_issue_split HIGH surfacing (paired) ==\033[0m\n'

  gh_issue_json() {
    echo '{"number":1,"title":"Test","body":"body","url":"https://github.com/t/r/issues/1","comments":[],"labels":[],"assignees":[]}'
  }
  export -f gh_issue_json
  safe_repo_main() { echo "$TMPDIR_BASE/repo"; }
  export -f safe_repo_main
  require_cmds() { true; }
  export -f require_cmds

  # T12: HIGH band -> MUST surface
  analyze_issue_for_split() {
    cat <<'EOF'
{"should_split":false,"reasoning":"atomic","sub_issues":[],"complexity":{"dims":{"files_touched":3,"loc_estimate":3,"novelty":3,"context_depth":3,"cross_module_fan_out":1},"loc_estimate_total":200,"files_estimate_total":3,"atomic_justification":null,"score":13,"band":"HIGH","decomposition_required":true,"size_flag":{"loc_exceeds":false,"files_exceeds":false,"decomposition_review_required":false}}}
EOF
  }
  export -f analyze_issue_for_split

  local high_output
  set +e
  high_output="$(cmd_issue_split "fakerepo" "1" --yes 2>&1)"
  set -e

  assert_contains "T12: HIGH surfacing" "$high_output" "MUST PROPOSE decomposition"

  # T13: LOW band -> does NOT surface
  analyze_issue_for_split() {
    cat <<'EOF'
{"should_split":false,"reasoning":"trivial","sub_issues":[],"complexity":{"dims":{"files_touched":1,"loc_estimate":1,"novelty":1,"context_depth":1,"cross_module_fan_out":1},"loc_estimate_total":50,"files_estimate_total":1,"atomic_justification":null,"score":5,"band":"LOW","decomposition_required":false,"size_flag":{"loc_exceeds":false,"files_exceeds":false,"decomposition_review_required":false}}}
EOF
  }
  export -f analyze_issue_for_split

  local low_output
  set +e
  low_output="$(cmd_issue_split "fakerepo" "1" --yes 2>&1)"
  set -e

  assert_not_contains "T13: LOW silence" "$low_output" "MUST PROPOSE decomposition"

  unset -f gh_issue_json safe_repo_main require_cmds analyze_issue_for_split
}

# ──────────────────────────────────────
# T14: cmd_issue_split size-review surfacing
# ──────────────────────────────────────
test_cmd_split_size_review_surfacing() {
  printf '\n\033[1m== T14: cmd_issue_split size-review surfacing ==\033[0m\n'

  gh_issue_json() {
    echo '{"number":2,"title":"Huge","body":"big","url":"https://github.com/t/r/issues/2","comments":[],"labels":[],"assignees":[]}'
  }
  export -f gh_issue_json
  safe_repo_main() { echo "$TMPDIR_BASE/repo"; }
  export -f safe_repo_main
  require_cmds() { true; }
  export -f require_cmds

  analyze_issue_for_split() {
    cat <<'EOF'
{"should_split":false,"reasoning":"big but focused","sub_issues":[],"complexity":{"dims":{"files_touched":1,"loc_estimate":1,"novelty":1,"context_depth":1,"cross_module_fan_out":1},"loc_estimate_total":900,"files_estimate_total":3,"atomic_justification":null,"score":5,"band":"LOW","decomposition_required":false,"size_flag":{"loc_exceeds":true,"files_exceeds":false,"decomposition_review_required":true}}}
EOF
  }
  export -f analyze_issue_for_split

  local output
  set +e
  output="$(cmd_issue_split "fakerepo" "2" --yes 2>&1)"
  set -e

  assert_contains "T14: size-review surfacing" "$output" "decomposition review before build"

  unset -f gh_issue_json safe_repo_main require_cmds analyze_issue_for_split
}

# ──────────────────────────────────────
# T15: planning blocks contain scoring instruction (all 3 modes)
# ──────────────────────────────────────
test_planning_blocks_contain_scoring() {
  printf '\n\033[1m== T15: planning blocks contain scoring instruction ==\033[0m\n'

  local full_out lite_out quick_out
  full_out="$(planning_block_full "$TMPDIR_BASE" 2>/dev/null)"
  lite_out="$(planning_block_lite "$TMPDIR_BASE" 2>/dev/null)"
  quick_out="$(planning_block_quick "$TMPDIR_BASE" 2>/dev/null)"

  for mode in full lite quick; do
    local out_var="${mode}_out"
    local out="${!out_var}"

    assert_contains "$mode: has Complexity Score header" "$out" "## Complexity Score"
    assert_contains "$mode: has 5-dim mention" "$out" "5-dim"
    assert_contains "$mode: has substituted LOW_MAX cutoff (<= 7)" "$out" "<= 7"
    assert_contains "$mode: has substituted MED_MAX cutoff (> 11)" "$out" "> 11"

    # DEFECT-2: ensure raw placeholders are NOT present
    assert_not_contains "$mode: no raw __COMPLEXITY_LOW_MAX__" "$out" "__COMPLEXITY_LOW_MAX__"
    assert_not_contains "$mode: no raw __COMPLEXITY_MED_MAX__" "$out" "__COMPLEXITY_MED_MAX__"
  done
}

# ──────────────────────────────────────
# T16: validate_prompt_md sentinel
# ──────────────────────────────────────
test_validate_prompt_md_sentinel() {
  printf '\n\033[1m== T16: validate_prompt_md sentinel ==\033[0m\n'

  # Render a real PROMPT.md (lite) and verify it validates
  local tmp_out="$TMPDIR_BASE/prompt.md"
  planning_block_lite "$TMPDIR_BASE" > "$tmp_out" 2>/dev/null

  # Must validate successfully (no unsubstituted tokens)
  if validate_prompt_md "$tmp_out" single; then
    pass "validate_prompt_md rc=0 (clean)"
  else
    fail "validate_prompt_md rc=0 (clean)" "returned non-zero"
  fi

  # Must NOT contain raw placeholder tokens
  local content
  content="$(cat "$tmp_out")"
  assert_not_contains "no raw __LOC_DECOMP_THRESHOLD__" "$content" "__LOC_DECOMP_THRESHOLD__"
  assert_not_contains "no raw __FILES_DECOMP_THRESHOLD__" "$content" "__FILES_DECOMP_THRESHOLD__"
  assert_not_contains "no raw __COMPLEXITY_LOW_MAX__" "$content" "__COMPLEXITY_LOW_MAX__"
  assert_not_contains "no raw __COMPLEXITY_MED_MAX__" "$content" "__COMPLEXITY_MED_MAX__"
}

# ──────────────────────────────────────
# T17: stage_manifest SPEC.md gate (GAP-1)
# ──────────────────────────────────────
test_stage_manifest_spec_gate() {
  printf '\n\033[1m== T17: stage_manifest SPEC.md gate ==\033[0m\n'

  local spec_dir="$TMPDIR_BASE/gate-spec"
  mkdir -p "$spec_dir/plans"

  # Case A: SPEC.md WITH ## Complexity Score -> passes
  cat > "$spec_dir/plans/SPEC.md" <<'EOF'
## Complexity Score
score: 8 (band MED)
## Pi Model Recommendation
suggested_pi_model: codex
EOF

  set +e
  validate_stage_artifacts "$spec_dir" lite 3
  local rc_a=$?
  set -e
  if [ "$rc_a" -eq 0 ]; then
    pass "T17a: SPEC with ## Complexity Score passes gate"
  else
    fail "T17a: SPEC with ## Complexity Score passes gate" "returned $rc_a"
  fi

  # Case B: SPEC.md WITHOUT ## Complexity Score -> fails
  cat > "$spec_dir/plans/SPEC.md" <<'EOF'
## Pi Model Recommendation
suggested_pi_model: codex
EOF

  set +e
  validate_stage_artifacts "$spec_dir" lite 3
  local rc_b=$?
  set -e
  if [ "$rc_b" -ne 0 ]; then
    pass "T17b: SPEC without ## Complexity Score fails gate"
  else
    fail "T17b: SPEC without ## Complexity Score fails gate" "returned 0 (should fail)"
  fi

  # Also test full:5 and quick:1 modes
  # full:5
  cat > "$spec_dir/plans/SPEC.md" <<'EOF'
## Complexity Score
score: 5 (band LOW)
EOF
  set +e
  validate_stage_artifacts "$spec_dir" full 5
  local rc_full=$?
  set -e
  if [ "$rc_full" -eq 0 ]; then
    pass "T17c: full:5 gate passes with Complexity Score"
  else
    fail "T17c: full:5 gate passes with Complexity Score" "returned $rc_full"
  fi

  # quick:1 without ## Complexity Score -> fails
  cat > "$spec_dir/plans/SPEC.md" <<'EOF'
## Pi Model Recommendation
EOF
  set +e
  validate_stage_artifacts "$spec_dir" quick 1
  local rc_quick=$?
  set -e
  if [ "$rc_quick" -ne 0 ]; then
    pass "T17d: quick:1 gate fails without Complexity Score"
  else
    fail "T17d: quick:1 gate fails without Complexity Score" "returned 0 (should fail)"
  fi
}

# ──────────────────────────────────────
# T18: Non-integer threshold env vars don't crash
# ──────────────────────────────────────
test_non_integer_threshold_graceful() {
  printf '\n\033[1m== T18: Non-integer threshold graceful ==\033[0m\n'

  local result
  result="$(ACORN_COMPLEXITY_LOW_MAX=abc ACORN_COMPLEXITY_MED_MAX=xyz complexity_band 10)"
  assert_eq "non-int thresholds fall back -> MED" "$result" "MED"

  local result2
  result2="$(ACORN_LOC_DECOMP_THRESHOLD=bad ACORN_FILES_DECOMP_THRESHOLD=bad check_size_thresholds 900 10)"
  assert_eq "non-int thresholds fall back -> true" "$result2" "true"
}

# ──────────────────────────────────────
# Run all tests
# ──────────────────────────────────────
setup

test_complexity_band_boundaries
test_complexity_band_config_override
test_complexity_band_non_numeric
test_check_size_thresholds_loc
test_check_size_thresholds_files
test_check_size_thresholds_config_override
test_enrich_complexity_computes_band
test_enrich_complexity_size_independent_of_band
test_enrich_complexity_legacy_pass_through
test_analyze_extended_complexity
test_analyze_backward_compat
test_cmd_split_high_surfacing_paired
test_cmd_split_size_review_surfacing
test_planning_blocks_contain_scoring
test_validate_prompt_md_sentinel
test_stage_manifest_spec_gate
test_non_integer_threshold_graceful

teardown

printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
