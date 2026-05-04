#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'

# test_approve_commit.sh -- T1..T12 for commit_spec_dir / commit_spec_dir_on_branch
# / amend_spec_metadata / cmd_approve, per SPEC #154 §5.
#
# Note: -e is intentionally OFF. Tests that expect `die` (which calls `exit 1`)
# wrap the call in `( ... )` to capture the exit; PASS/FAIL counters live in
# the parent shell, not the test bodies, so cd/cleanup pattern is used instead
# of `( cd $d; ... )` subshells.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACORN_SCRIPT="${ACORN_SCRIPT:-$SCRIPT_DIR/bin/acorn}"
[ -f "$ACORN_SCRIPT" ] || { echo "ACORN_SCRIPT not found: $ACORN_SCRIPT" >&2; exit 1; }

eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"

PASS=0
FAIL=0

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

setup_test_repo() {
  local d
  d="$(mktemp -d)"
  (
    cd "$d"
    git init -q
    git config user.email test@example.com
    git config user.name Test
    git checkout -b main 2>/dev/null || git checkout main 2>/dev/null || true
    git commit --allow-empty -q -m "init"
  )
  mkdir -p "$d/.specs/test-slug/plans"
  printf 'placeholder\n' > "$d/.specs/test-slug/PROMPT.md"
  printf '# spec\n' > "$d/.specs/test-slug/plans/SPEC.md"
  printf '%s' "$d"
}

ORIGINAL_CWD="$PWD"
cleanup_dir() { cd "$ORIGINAL_CWD"; rm -rf "$1" 2>/dev/null; }

# T1
test_commit_spec_dir_creates_commit() {
  local d; d="$(setup_test_repo)"
  cd "$d"
  commit_spec_dir "test-slug" "$d"
  local subject; subject="$(git log -1 --format=%s)"
  assert_eq "T1 commit subject" "$subject" "spec: commit test-slug for dispatch (acorn approve)"
  if git show HEAD --name-only | grep -q "metadata.json"; then
    fail "T1 metadata.json absent" "metadata.json should not be in HEAD when extract_script unavailable"
  else
    pass "T1 metadata.json absent"
  fi
  assert_eq "T1 caller branch" "$(git symbolic-ref --short HEAD)" "main"
  cleanup_dir "$d"
}

# T2
test_commit_spec_dir_idempotent() {
  local d; d="$(setup_test_repo)"
  cd "$d"
  commit_spec_dir "test-slug" "$d"
  local count1; count1="$(git rev-list HEAD --count)"
  commit_spec_dir "test-slug" "$d"
  local count2; count2="$(git rev-list HEAD --count)"
  assert_eq "T2 idempotent commit count" "$count2" "$count1"
  cleanup_dir "$d"
}

# T3
test_commit_spec_dir_restores_caller_branch() {
  local d; d="$(setup_test_repo)"
  cd "$d"
  git checkout -q -b feature/foo
  commit_spec_dir "test-slug" "$d"
  assert_eq "T3 caller branch restored" "$(git symbolic-ref --short HEAD)" "feature/foo"
  if git rev-list main -- ".specs/test-slug" | grep -q .; then
    pass "T3 spec on main"
  else
    fail "T3 spec on main" "spec commit not on main"
  fi
  if git rev-list feature/foo -- ".specs/test-slug" | grep -q .; then
    fail "T3 spec NOT on feature" "spec commit unexpectedly on feature/foo"
  else
    pass "T3 spec NOT on feature"
  fi
  cleanup_dir "$d"
}

# T3b
test_commit_spec_dir_ignores_staged_unrelated() {
  local d; d="$(setup_test_repo)"
  cd "$d"
  printf 'unrelated content\n' > unrelated.txt
  git add unrelated.txt
  commit_spec_dir "test-slug" "$d"
  if git show HEAD --name-only | grep -q "^unrelated.txt$"; then
    fail "T3b unrelated not swept" "unrelated.txt was committed in spec commit"
  else
    pass "T3b unrelated not swept"
  fi
  if git diff --cached --name-only | grep -q "^unrelated.txt$"; then
    pass "T3b unrelated still staged"
  else
    fail "T3b unrelated still staged" "unrelated.txt no longer staged after commit_spec_dir"
  fi
  cleanup_dir "$d"
}

# T4 -- die-expected; subshell-wrap commit_spec_dir
test_commit_spec_dir_dies_on_detached_head() {
  local d; d="$(setup_test_repo)"
  cd "$d"
  git checkout -q --detach HEAD
  local rc=0
  ( commit_spec_dir "test-slug" "$d" ) 2>/tmp/acorn_t4_err >/dev/null || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "T4 detached HEAD" "expected die() but commit_spec_dir succeeded"
  else
    if grep -q "detached HEAD" /tmp/acorn_t4_err; then
      pass "T4 detached HEAD"
    else
      fail "T4 detached HEAD" "expected 'detached HEAD' in error: $(cat /tmp/acorn_t4_err)"
    fi
  fi
  rm -f /tmp/acorn_t4_err
  cleanup_dir "$d"
}

# T5
test_acorn_commit_branch_env() {
  local d; d="$(setup_test_repo)"
  cd "$d"
  git checkout -q -b custom-specs
  git checkout -q main
  ACORN_COMMIT_BRANCH=custom-specs commit_spec_dir "test-slug" "$d"
  if git rev-list custom-specs -- ".specs/test-slug" | grep -q .; then
    pass "T5 spec on custom-specs"
  else
    fail "T5 spec on custom-specs" "spec not committed to custom-specs"
  fi
  if git rev-list main -- ".specs/test-slug" 2>/dev/null | grep -q .; then
    fail "T5 spec NOT on main" "spec unexpectedly on main"
  else
    pass "T5 spec NOT on main"
  fi
  cleanup_dir "$d"
}

# T6
test_orphan_branch_creates_and_restores() {
  local d; d="$(setup_test_repo)"
  cd "$d"
  git checkout -q -b feature/foo
  local before; before="$(git symbolic-ref --short HEAD)"
  commit_spec_dir_on_branch "test-slug" "$d" "specs-archive"
  local after; after="$(git symbolic-ref --short HEAD)"
  assert_eq "T6 caller branch restored" "$after" "$before"
  if git rev-parse --verify specs-archive >/dev/null 2>&1; then
    pass "T6 specs-archive created"
  else
    fail "T6 specs-archive created" "specs-archive branch not created"
  fi
  if git rev-list specs-archive -- ".specs/test-slug" | grep -q .; then
    pass "T6 spec on specs-archive"
  else
    fail "T6 spec on specs-archive" "spec not committed on specs-archive"
  fi
  cleanup_dir "$d"
}

# T7
test_orphan_branch_existing() {
  local d; d="$(setup_test_repo)"
  cd "$d"
  git checkout -q -b specs-archive
  git commit -q --allow-empty -m "preexisting"
  git checkout -q main
  commit_spec_dir_on_branch "test-slug" "$d" "specs-archive"
  local count; count="$(git rev-list specs-archive --count)"
  assert_eq "T7 commit count on specs-archive" "$count" "3"
  assert_eq "T7 caller branch" "$(git symbolic-ref --short HEAD)" "main"
  cleanup_dir "$d"
}

# T8 -- cmd_approve end-to-end
test_cmd_approve_end_to_end() {
  local d; d="$(setup_test_repo)"
  mv "$d/.specs/test-slug" "$d/.specs/42-test-slug"
  cd "$d"
  safe_repo_main() { printf '%s' "$d"; }
  spec_dir() { printf '%s/.specs/%s' "$d" "$2"; }
  repo_main_path() { printf '%s' "$d"; }
  gh() { return 0; }
  set_issue_state_label() { :; }
  comment_issue() { :; }
  notify_telegram() { :; }
  FOREMAN_HOME=/nonexistent cmd_approve "fake-repo" "42-test-slug" >/dev/null
  local subject; subject="$(git log -1 --format=%s)"
  assert_eq "T8 commit subject" "$subject" "spec: commit 42-test-slug for dispatch (acorn approve)"
  assert_eq "T8 caller branch" "$(git symbolic-ref --short HEAD)" "main"
  unset -f safe_repo_main spec_dir repo_main_path gh set_issue_state_label comment_issue notify_telegram
  cleanup_dir "$d"
}

# T9 -- die-expected; subshell-wrap cmd_approve
test_mutual_exclusion() {
  local d; d="$(setup_test_repo)"
  mv "$d/.specs/test-slug" "$d/.specs/42-test-slug"
  cd "$d"
  safe_repo_main() { printf '%s' "$d"; }
  spec_dir() { printf '%s/.specs/%s' "$d" "$2"; }
  repo_main_path() { printf '%s' "$d"; }
  gh() { return 0; }
  set_issue_state_label() { :; }
  comment_issue() { :; }
  notify_telegram() { :; }
  export -f safe_repo_main spec_dir repo_main_path gh set_issue_state_label comment_issue notify_telegram
  local rc=0
  ( cmd_approve "fake-repo" "42-test-slug" --no-commit --orphan-branch x ) 2>/tmp/acorn_t9_err >/dev/null || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "T9 mutual exclusion" "expected die() but cmd_approve succeeded"
  else
    if grep -q "mutually exclusive" /tmp/acorn_t9_err; then
      pass "T9 mutual exclusion"
    else
      fail "T9 mutual exclusion" "expected 'mutually exclusive' error, got: $(cat /tmp/acorn_t9_err)"
    fi
  fi
  rm -f /tmp/acorn_t9_err
  unset -f safe_repo_main spec_dir repo_main_path gh set_issue_state_label comment_issue notify_telegram
  cleanup_dir "$d"
}

# T10
test_no_commit_flag() {
  local d; d="$(setup_test_repo)"
  mv "$d/.specs/test-slug" "$d/.specs/42-test-slug"
  cd "$d"
  safe_repo_main() { printf '%s' "$d"; }
  spec_dir() { printf '%s/.specs/%s' "$d" "$2"; }
  repo_main_path() { printf '%s' "$d"; }
  gh() { return 0; }
  set_issue_state_label() { :; }
  comment_issue() { :; }
  notify_telegram() { :; }
  local before_count; before_count="$(git rev-list HEAD --count)"
  FOREMAN_HOME=/nonexistent cmd_approve "fake-repo" "42-test-slug" --no-commit >/dev/null
  local after_count; after_count="$(git rev-list HEAD --count)"
  assert_eq "T10 no commit when --no-commit" "$after_count" "$before_count"
  unset -f safe_repo_main spec_dir repo_main_path gh set_issue_state_label comment_issue notify_telegram
  cleanup_dir "$d"
}

# T11
test_amend_folds_metadata() {
  local d; d="$(setup_test_repo)"
  cd "$d"
  commit_spec_dir "test-slug" "$d"
  local before_sha; before_sha="$(git rev-parse HEAD)"
  local before_count; before_count="$(git rev-list HEAD --count)"
  printf '{"v":1,"slug":"test-slug"}\n' > .specs/test-slug/metadata.json
  amend_spec_metadata "test-slug" "$d"
  local after_sha; after_sha="$(git rev-parse HEAD)"
  local after_count; after_count="$(git rev-list HEAD --count)"
  if [ "$before_sha" != "$after_sha" ]; then
    pass "T11 amend changed HEAD"
  else
    fail "T11 amend changed HEAD" "amend did not change HEAD sha"
  fi
  if git show HEAD --name-only | grep -q "metadata.json"; then
    pass "T11 metadata.json in HEAD"
  else
    fail "T11 metadata.json in HEAD" "metadata.json not in amended HEAD"
  fi
  assert_eq "T11 commit count unchanged" "$after_count" "$before_count"
  cleanup_dir "$d"
}

# T12
test_amend_standalone_when_head_moved() {
  local d; d="$(setup_test_repo)"
  cd "$d"
  commit_spec_dir "test-slug" "$d"
  git commit -q --allow-empty -m "unrelated commit"
  local before_count; before_count="$(git rev-list HEAD --count)"
  printf '{"v":1,"slug":"test-slug"}\n' > .specs/test-slug/metadata.json
  amend_spec_metadata "test-slug" "$d"
  local after_count; after_count="$(git rev-list HEAD --count)"
  local expected=$((before_count + 1))
  assert_eq "T12 +1 commit" "$after_count" "$expected"
  local subject; subject="$(git log -1 --format=%s)"
  assert_eq "T12 standalone subject" "$subject" "spec: metadata for test-slug"
  cleanup_dir "$d"
}

test_commit_spec_dir_creates_commit
test_commit_spec_dir_idempotent
test_commit_spec_dir_restores_caller_branch
test_commit_spec_dir_ignores_staged_unrelated
test_commit_spec_dir_dies_on_detached_head
test_acorn_commit_branch_env
test_orphan_branch_creates_and_restores
test_orphan_branch_existing
test_cmd_approve_end_to_end
test_mutual_exclusion
test_no_commit_flag
test_amend_folds_metadata
test_amend_standalone_when_head_moved

printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
