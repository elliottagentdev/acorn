#!/usr/bin/env bash
# E2E smoke test: real tmux, real Forged, validates event emission.
# Expected runtime: up to 210s.
set -euo pipefail

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }

FOREMAN_HOME="${FOREMAN_HOME:-$HOME/.foreman}"
PROJECTS_DIR="${PROJECTS_DIR:-/mnt/e/agentdev/projects}"
REPO="forge"
SLUG="e2e-idle-test-$(date +%s)"
SESSION="${REPO}_specs_${SLUG}_claude"
SPEC_DIR="$PROJECTS_DIR/$REPO/main/.specs/$SLUG"
MARKER_DIR="$FOREMAN_HOME/watchdog-state"
EVENTS="$FOREMAN_HOME/.foreman-events.jsonl"

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -f "$MARKER_DIR/launch_$SESSION"
  rm -rf "$SPEC_DIR"
}
trap cleanup EXIT

mkdir -p "$SPEC_DIR/recon" "$MARKER_DIR"
touch "$MARKER_DIR/launch_$SESSION"
tmux new-session -d -s "$SESSION" -c "$FOREMAN_HOME" bash
curl -sf --max-time 3 -X POST -H "Content-Type: application/json" \
  -d "{\"session\":\"$SESSION\",\"type\":\"acorn\"}" \
  http://127.0.0.1:7700/register 2>/dev/null || true

echo "Waiting up to 210s for idle detection events..."
DETECTED=false; RETRY=false; ALERT=false
DEADLINE=$(($(date +%s) + 210))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  sleep 10
  grep -q "acorn_idle_detected.*$SESSION" "$EVENTS" 2>/dev/null && DETECTED=true
  grep -q "acorn_prompt_retry.*$SESSION" "$EVENTS" 2>/dev/null && RETRY=true
  if grep -q "acorn_alert_sent.*$SESSION" "$EVENTS" 2>/dev/null; then
    ALERT=true; break
  fi
done

$DETECTED && pass "E2E: acorn_idle_detected emitted" || fail "E2E: acorn_idle_detected NOT emitted"
$RETRY   && pass "E2E: acorn_prompt_retry emitted"   || fail "E2E: acorn_prompt_retry NOT emitted"
$ALERT   && pass "E2E: acorn_alert_sent emitted"     || fail "E2E: acorn_alert_sent NOT emitted"

# False-positive check: session with recon output should not be flagged
CLEAN="${REPO}_specs_${SLUG}-clean_claude"
CLEAN_DIR="$PROJECTS_DIR/$REPO/main/.specs/${SLUG}-clean"
mkdir -p "$CLEAN_DIR/recon"
echo "# output" > "$CLEAN_DIR/recon/architecture.md"
touch "$MARKER_DIR/launch_$CLEAN"
tmux new-session -d -s "$CLEAN" -c "$FOREMAN_HOME" bash 2>/dev/null || true
sleep 35
grep -q "\"session\":\"$CLEAN\"" "$EVENTS" 2>/dev/null \
  && fail "E2E: false positive — clean session flagged" \
  || pass "E2E: zero false positives on session with recon output"
tmux kill-session -t "$CLEAN" 2>/dev/null || true
rm -f "$MARKER_DIR/launch_$CLEAN"; rm -rf "$CLEAN_DIR"

echo "E2E: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
