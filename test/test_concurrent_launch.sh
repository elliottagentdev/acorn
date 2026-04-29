#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# test_concurrent_launch.sh -- Concurrent launch test (A4)
# Gated behind INTEGRATION=1.
# Verifies 3 concurrent spec directories get CLAUDE.md and watchdog detects them.

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }
assert_eq() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "expected '$3', got '$2'"; }

if [ "${INTEGRATION:-0}" -ne 1 ]; then
    echo "Skipping integration test (set INTEGRATION=1 to run)"
    exit 0
fi

TMPDIR_BASE="$(mktemp -d)"
teardown() { rm -rf "$TMPDIR_BASE"; }
trap teardown EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACORN_SCRIPT="$SCRIPT_DIR/bin/acorn"

export HOME="$TMPDIR_BASE"
export FOREMAN_HOME="$TMPDIR_BASE/.foreman"
export PROJECTS_DIR="$TMPDIR_BASE/projects"
mkdir -p "$FOREMAN_HOME/watchdog-state" "$FOREMAN_HOME/logs" "$FOREMAN_HOME/bin" "$PROJECTS_DIR/testrepo/main/.specs"

# Copy watchdog script
cp "$HOME/../.foreman/bin/completion-watchdog.sh" "$FOREMAN_HOME/bin/" 2>/dev/null \
  || cp /home/agentdev/.foreman/bin/completion-watchdog.sh "$FOREMAN_HOME/bin/" 2>/dev/null \
  || { echo "FATAL: cannot find completion-watchdog.sh"; exit 1; }
chmod +x "$FOREMAN_HOME/bin/completion-watchdog.sh"

# Source acorn functions without triggering main()
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"

# Create 3 spec directories with PROMPT.md
for i in 1 2 3; do
    spec_dir="$PROJECTS_DIR/testrepo/main/.specs/${i}-test-concurrent"
    mkdir -p "$spec_dir"
    printf '# Test prompt %d\n' "$i" > "$spec_dir/PROMPT.md"
done

# Write CLAUDE.md for each
for i in 1 2 3; do
    spec_dir="$PROJECTS_DIR/testrepo/main/.specs/${i}-test-concurrent"
    write_spec_claude_md "$spec_dir" "quick"
done

# Verify all 3 CLAUDE.md files exist
for i in 1 2 3; do
    spec_dir="$PROJECTS_DIR/testrepo/main/.specs/${i}-test-concurrent"
    [ -f "$spec_dir/CLAUDE.md" ] && pass "CLAUDE.md exists for session $i" || fail "CLAUDE.md exists for session $i" "file missing"
done

# Create mock world.yaml with 3 pipelines
cat > "$FOREMAN_HOME/world.yaml" <<'YAML'
active_acorn_pipelines:
- repo: testrepo
  issue: 1
  slug: 1-test-concurrent
  session: testrepo_specs_1-test-concurrent_claude
  mode: quick
  agent_weight: 4
  provider: anthropic
  pipeline_complete: false
- repo: testrepo
  issue: 2
  slug: 2-test-concurrent
  session: testrepo_specs_2-test-concurrent_claude
  mode: quick
  agent_weight: 4
  provider: anthropic
  pipeline_complete: false
- repo: testrepo
  issue: 3
  slug: 3-test-concurrent
  session: testrepo_specs_3-test-concurrent_claude
  mode: quick
  agent_weight: 4
  provider: anthropic
  pipeline_complete: false
active_pi_sessions: []
YAML

# Simulate completions: create SPEC.md in each
for i in 1 2 3; do
    mkdir -p "$PROJECTS_DIR/testrepo/main/.specs/${i}-test-concurrent/plans"
    printf '# SPEC\n' > "$PROJECTS_DIR/testrepo/main/.specs/${i}-test-concurrent/plans/SPEC.md"
done

# Run watchdog in dry-run mode
watchdog_output="$(bash "$FOREMAN_HOME/bin/completion-watchdog.sh" --dry-run 2>&1)" || true
for i in 1 2 3; do
    if printf '%s' "$watchdog_output" | grep -q "${i}-test-concurrent"; then
        pass "Watchdog detected session $i completion"
    else
        fail "Watchdog detected session $i completion" "not found in watchdog output"
    fi
done

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
