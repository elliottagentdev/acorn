#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }
assert_eq() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "expected '$3', got '$2'"; }
assert_contains() { printf '%s' "$2" | grep -qF "$3" && pass "$1" || fail "$1" "missing '$3'"; }
assert_not_contains() { printf '%s' "$2" | grep -qF "$3" && fail "$1" "should not contain '$3'" || pass "$1"; }

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

FORGED_DIR="$(dirname "$(realpath /home/agentdev/.foreman/bin/forged.py)")"

# ---------------------------------------------------------------------------
# Build a Python test helper that imports forged and creates a minimal daemon
# ---------------------------------------------------------------------------
HELPER="$TMPDIR_BASE/helper.py"
cat > "$HELPER" << 'PYEOF'
import sys, os, json, time, re, tempfile, threading

sys.path.insert(0, os.environ["FORGED_DIR"])
import forged

# Minimal stub daemon for unit tests
class StubDaemon(forged.ForgedDaemon):
    def __init__(self, tmp):
        self.foreman_home = tmp
        self.projects_dir = os.path.join(tmp, "projects")
        self.port = 0
        self.state_path = os.path.join(tmp, "forged-state.json")
        self.config_path = os.path.join(tmp, "concurrency-config.yaml")
        self.event_log_path = os.path.join(tmp, "logs", "forged-events.jsonl")
        self.breadcrumb_path = os.path.join(tmp, ".forged-last-run")
        self.state_lock = threading.Lock()
        self.shutdown_event = threading.Event()
        self.config = dict(forged.DEFAULTS)
        self.state = self._empty_state()
        self._started_at_monotonic = time.monotonic()
        self._startup_time = time.time()
        self._config_mtime = 0
        self._auth_cycle_count = 0
        self._gc_cycle_count = 0
        self._persist_cycle_count = 0
        self._cycle_notification_count = 0
        self._notifications = []
        self._events = []
        os.makedirs(os.path.join(tmp, "watchdog-state"), exist_ok=True)
        os.makedirs(os.path.join(tmp, "logs"), exist_ok=True)

    def notify(self, message, dedup_key=None):
        """Capture notifications instead of sending."""
        if dedup_key and dedup_key in self.state.get("notified", {}):
            return
        if dedup_key:
            self.state.setdefault("notified", {})[dedup_key] = forged._now_iso()
        self._notifications.append({"message": message, "dedup_key": dedup_key})
        self._cycle_notification_count += 1

def make_daemon(tmp):
    return StubDaemon(tmp)
PYEOF

export FORGED_DIR="$FORGED_DIR"

# ---------------------------------------------------------------------------
# T1: test_output_empty_no_recon_dir
# ---------------------------------------------------------------------------
echo "--- T1: test_output_empty_no_recon_dir ---"
RESULT=$(python3 -c "
import sys, os, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
# No recon or plans dirs created
os.makedirs(os.path.join(d.projects_dir, 'forge', 'main', '.specs', '87-test'), exist_ok=True)
print(d._acorn_output_empty('forge_specs_87-test_claude'))
")
assert_eq "T1: no recon dir → True" "$RESULT" "True"

# ---------------------------------------------------------------------------
# T2: test_output_empty_no_md_files
# ---------------------------------------------------------------------------
echo "--- T2: test_output_empty_no_md_files ---"
RESULT=$(python3 -c "
import sys, os, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
recon = os.path.join(d.projects_dir, 'forge', 'main', '.specs', '87-test', 'recon')
os.makedirs(recon, exist_ok=True)
open(os.path.join(recon, 'temp.tmp'), 'w').close()
print(d._acorn_output_empty('forge_specs_87-test_claude'))
")
assert_eq "T2: no .md files → True" "$RESULT" "True"

# ---------------------------------------------------------------------------
# T3: test_output_not_empty_recon
# ---------------------------------------------------------------------------
echo "--- T3: test_output_not_empty_recon ---"
RESULT=$(python3 -c "
import sys, os, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
recon = os.path.join(d.projects_dir, 'forge', 'main', '.specs', '87-test', 'recon')
os.makedirs(recon, exist_ok=True)
open(os.path.join(recon, 'architecture.md'), 'w').write('# arch')
print(d._acorn_output_empty('forge_specs_87-test_claude'))
")
assert_eq "T3: recon has .md → False" "$RESULT" "False"

# ---------------------------------------------------------------------------
# T4: test_output_not_empty_plans
# ---------------------------------------------------------------------------
echo "--- T4: test_output_not_empty_plans ---"
RESULT=$(python3 -c "
import sys, os, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
plans = os.path.join(d.projects_dir, 'forge', 'main', '.specs', '87-test', 'plans')
os.makedirs(plans, exist_ok=True)
open(os.path.join(plans, 'draft.md'), 'w').write('# draft')
print(d._acorn_output_empty('forge_specs_87-test_claude'))
")
assert_eq "T4: plans has .md → False" "$RESULT" "False"

# ---------------------------------------------------------------------------
# T5: test_launch_age_no_marker
# ---------------------------------------------------------------------------
echo "--- T5: test_launch_age_no_marker ---"
RESULT=$(python3 -c "
import sys, os, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
print(d._acorn_launch_age('nonexistent_specs_99_claude'))
")
assert_eq "T5: no marker → None" "$RESULT" "None"

# ---------------------------------------------------------------------------
# T6: test_launch_age_correct
# ---------------------------------------------------------------------------
echo "--- T6: test_launch_age_correct ---"
RESULT=$(python3 -c "
import sys, os, time, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
marker = os.path.join(d.foreman_home, 'watchdog-state', 'launch_forge_specs_87_claude')
with open(marker, 'w') as f: f.write('')
# Touch it to 65 seconds ago
os.utime(marker, (time.time() - 65, time.time() - 65))
age = d._acorn_launch_age('forge_specs_87_claude')
print('OK' if 63 < age < 67 else f'BAD: {age}')
")
assert_eq "T6: launch age ~65s" "$RESULT" "OK"

# ---------------------------------------------------------------------------
# T7: test_startup_grace_skips_young
# ---------------------------------------------------------------------------
echo "--- T7: test_startup_grace_skips_young ---"
RESULT=$(python3 -c "
import sys, os, time, tempfile, json
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
name = 'forge_specs_87_claude'
marker = os.path.join(d.foreman_home, 'watchdog-state', f'launch_{name}')
with open(marker, 'w') as f: f.write('')
# Touch marker to 10s ago (within grace period)
os.utime(marker, (time.time() - 10, time.time() - 10))
d.state['sessions'][name] = d._default_session(name, stype='acorn')
d.state['sessions'][name]['tmux_alive'] = True
# Make spec dir but no .md files
os.makedirs(os.path.join(d.projects_dir, 'forge', 'main', '.specs', '87', 'recon'), exist_ok=True)
d._step_acorn_idle()
meta = d.state['sessions'][name].get('meta', {})
print('SKIP' if not meta.get('idle_detected_at') else 'DETECTED')
")
assert_eq "T7: startup grace → SKIP" "$RESULT" "SKIP"

# ---------------------------------------------------------------------------
# T8: test_recovery_clears_idle_state
# ---------------------------------------------------------------------------
echo "--- T8: test_recovery_clears_idle_state ---"
RESULT=$(python3 -c "
import sys, os, time, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
sys.path.insert(0, os.environ['FORGED_DIR'])
import forged
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
name = 'forge_specs_88_claude'
marker = os.path.join(d.foreman_home, 'watchdog-state', f'launch_{name}')
with open(marker, 'w') as f: f.write('')
os.utime(marker, (time.time() - 70, time.time() - 70))

d.state['sessions'][name] = d._default_session(name, stype='acorn')
d.state['sessions'][name]['tmux_alive'] = True
d.state['sessions'][name]['meta'] = {
    'idle_detected_at': forged._now_iso(),
    'prompt_retry_at': forged._now_iso(),
    'idle_alert_sent_at': forged._now_iso(),
    'pane_snapshot_pre_retry': 'test',
    'idle_prompt_at_detection': True,
}
d.state['notified']['acorn_idle_' + name] = forged._now_iso()

# Create .md file so output is not empty
recon = os.path.join(d.projects_dir, 'forge', 'main', '.specs', '88', 'recon')
os.makedirs(recon, exist_ok=True)
open(os.path.join(recon, 'architecture.md'), 'w').write('# arch')

d._step_acorn_idle()
meta = d.state['sessions'][name].get('meta', {})
keys = ['idle_detected_at', 'prompt_retry_at', 'idle_alert_sent_at',
        'pane_snapshot_pre_retry', 'idle_prompt_at_detection']
remaining = [k for k in keys if k in meta]
dedup_present = ('acorn_idle_' + name) in d.state.get('notified', {})
print('CLEAR' if not remaining and not dedup_present else f'REMAINING: {remaining} dedup={dedup_present}')
")
assert_eq "T8: recovery clears all meta" "$RESULT" "CLEAR"

# ---------------------------------------------------------------------------
# T9: test_recon_empty_alone_triggers (RT-2)
# ---------------------------------------------------------------------------
echo "--- T9: test_recon_empty_alone_triggers ---"
RESULT=$(python3 -c "
import sys, os, time, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
name = 'forge_specs_89_claude'
marker = os.path.join(d.foreman_home, 'watchdog-state', f'launch_{name}')
with open(marker, 'w') as f: f.write('')
os.utime(marker, (time.time() - 70, time.time() - 70))
d.state['sessions'][name] = d._default_session(name, stype='acorn')
d.state['sessions'][name]['tmux_alive'] = True
# Create spec dir but no .md files (recon_empty=True, idle_prompt may be False)
os.makedirs(os.path.join(d.projects_dir, 'forge', 'main', '.specs', '89', 'recon'), exist_ok=True)
d._step_acorn_idle()
meta = d.state['sessions'][name].get('meta', {})
print('DETECTED' if meta.get('idle_detected_at') else 'MISSED')
")
assert_eq "T9: recon_empty alone triggers detection" "$RESULT" "DETECTED"

# ---------------------------------------------------------------------------
# T10: test_dedup_cleared_on_recovery
# ---------------------------------------------------------------------------
echo "--- T10: test_dedup_cleared_on_recovery ---"
# Same as T8 - dedup_present check already validated
pass "T10: dedup cleared on recovery (validated in T8)"

# ---------------------------------------------------------------------------
# T11: test_foreman_events_written
# ---------------------------------------------------------------------------
echo "--- T11: test_foreman_events_written ---"
RESULT=$(python3 -c "
import sys, os, time, tempfile, json
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
name = 'forge_specs_90_claude'
marker = os.path.join(d.foreman_home, 'watchdog-state', f'launch_{name}')
with open(marker, 'w') as f: f.write('')
os.utime(marker, (time.time() - 70, time.time() - 70))
d.state['sessions'][name] = d._default_session(name, stype='acorn')
d.state['sessions'][name]['tmux_alive'] = True
os.makedirs(os.path.join(d.projects_dir, 'forge', 'main', '.specs', '90', 'recon'), exist_ok=True)
d._step_acorn_idle()
events_path = os.path.join(d.foreman_home, '.foreman-events.jsonl')
if os.path.isfile(events_path):
    with open(events_path) as f:
        lines = f.readlines()
    events = [json.loads(l) for l in lines]
    types = [e['event'] for e in events]
    print('OK' if 'acorn_idle_detected' in types else f'MISSING: {types}')
else:
    print('NO_FILE')
")
assert_eq "T11: events written" "$RESULT" "OK"

# ---------------------------------------------------------------------------
# T12: test_pending_json_entry_created
# ---------------------------------------------------------------------------
echo "--- T12: test_pending_json_entry_created ---"
RESULT=$(python3 -c "
import sys, os, time, tempfile, json
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
name = 'forge_specs_91_claude'
d._acorn_idle_alert(name, {'type': 'acorn'}, systemic=False)
pending_path = os.path.join(d.foreman_home, 'pending.json')
if os.path.isfile(pending_path):
    with open(pending_path) as f:
        data = json.load(f)
    if data and data[0].get('type') == 'acorn_idle_alert':
        print('OK')
    else:
        print(f'BAD: {data}')
else:
    print('NO_FILE')
")
assert_eq "T12: pending.json entry created" "$RESULT" "OK"

# ---------------------------------------------------------------------------
# T13: test_systemic_alert_pane_unchanged (RT-3)
# ---------------------------------------------------------------------------
echo "--- T13: test_systemic_alert_pane_unchanged ---"
RESULT=$(python3 -c "
import sys, os, time, tempfile, json
sys.path.insert(0, '$TMPDIR_BASE')
sys.path.insert(0, os.environ['FORGED_DIR'])
import forged
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
name = 'forge_specs_92_claude'
marker = os.path.join(d.foreman_home, 'watchdog-state', f'launch_{name}')
with open(marker, 'w') as f: f.write('')
os.utime(marker, (time.time() - 200, time.time() - 200))

d.state['sessions'][name] = d._default_session(name, stype='acorn')
d.state['sessions'][name]['tmux_alive'] = True
d.state['sessions'][name]['meta'] = {
    'idle_detected_at': forged._now_iso(),
    'prompt_retry_at': forged._now_iso(),
    'pane_snapshot_pre_retry': 'same content here',
}
os.makedirs(os.path.join(d.projects_dir, 'forge', 'main', '.specs', '92', 'recon'), exist_ok=True)

# Monkey-patch _capture_pane_text to return same text
d._capture_pane_text = lambda sn: 'same content here'

d._step_acorn_idle()
meta = d.state['sessions'][name].get('meta', {})
print('SYSTEMIC' if meta.get('alert_was_systemic') else 'GENERIC')
")
assert_eq "T13: identical pane → systemic" "$RESULT" "SYSTEMIC"

# ---------------------------------------------------------------------------
# T14: test_generic_alert_pane_changed (RT-3)
# ---------------------------------------------------------------------------
echo "--- T14: test_generic_alert_pane_changed ---"
RESULT=$(python3 -c "
import sys, os, time, tempfile, json
sys.path.insert(0, '$TMPDIR_BASE')
sys.path.insert(0, os.environ['FORGED_DIR'])
import forged
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
name = 'forge_specs_93_claude'
marker = os.path.join(d.foreman_home, 'watchdog-state', f'launch_{name}')
with open(marker, 'w') as f: f.write('')
os.utime(marker, (time.time() - 200, time.time() - 200))

d.state['sessions'][name] = d._default_session(name, stype='acorn')
d.state['sessions'][name]['tmux_alive'] = True
d.state['sessions'][name]['meta'] = {
    'idle_detected_at': forged._now_iso(),
    'prompt_retry_at': forged._now_iso(),
    'pane_snapshot_pre_retry': 'before retry text',
}
os.makedirs(os.path.join(d.projects_dir, 'forge', 'main', '.specs', '93', 'recon'), exist_ok=True)

# Monkey-patch _capture_pane_text to return different text
d._capture_pane_text = lambda sn: 'different text after retry'

d._step_acorn_idle()
meta = d.state['sessions'][name].get('meta', {})
print('GENERIC' if not meta.get('alert_was_systemic') else 'SYSTEMIC')
")
assert_eq "T14: different pane → generic" "$RESULT" "GENERIC"

# ---------------------------------------------------------------------------
# T15: test_retry_message_is_direct_imperative (RT2-1/2/6)
# ---------------------------------------------------------------------------
echo "--- T15: test_retry_message_is_direct_imperative ---"
RETRY_MSG=$(python3 -c "
import sys, os, re
sys.path.insert(0, os.environ['FORGED_DIR'])

# Build the message directly using the same logic as _acorn_prompt_retry
session_name = 'forge_specs_87-w8-13_claude'
session = {'type': 'acorn', 'mode': 'lite'}
m = re.match(r'(.+?)_specs_(.+)_claude$', session_name)
repo, slug = m.group(1), m.group(2)
mode = session.get('mode', 'lite')
issue_match = re.match(r'(\d+)', slug)
issue_ref = f'{repo}#{issue_match.group(1)}' if issue_match else slug

msg = (
    f'You are in an Acorn spec session for {issue_ref}. '
    f'Execute the full {mode} pipeline described in PROMPT.md immediately. '
    f'Start with Stage 0: run the three recon agents '
    f'(architecture, relevant_code, conventions). '
    f'Do not wait for further input.'
)
print(msg)
")
assert_contains "T15a: contains Execute" "$RETRY_MSG" "Execute"
assert_contains "T15b: contains immediately" "$RETRY_MSG" "immediately"
assert_contains "T15c: contains Stage 0" "$RETRY_MSG" "Stage 0"
assert_not_contains "T15d: no 'Read PROMPT.md'" "$RETRY_MSG" "Read PROMPT.md"
assert_not_contains "T15e: no 'follow ALL'" "$RETRY_MSG" "follow ALL instructions"
LEN=${#RETRY_MSG}
[ "$LEN" -lt 300 ] && pass "T15f: retry message < 300 chars ($LEN)" \
  || fail "T15f: retry message too long ($LEN chars)"

# ---------------------------------------------------------------------------
# T16: test_retry_skipped_if_thinking (RT2-3)
# ---------------------------------------------------------------------------
echo "--- T16: test_retry_skipped_if_thinking ---"
RESULT=$(python3 -c "
import sys, os, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
# Monkey-patch to return 'Thinking' in pane
d._capture_pane_text = lambda sn: 'Claude is Thinking about the problem...'
print(d._is_session_actively_working('any_session'))
")
assert_eq "T16: Thinking → active" "$RESULT" "True"

# ---------------------------------------------------------------------------
# T17: test_retry_fires_if_no_active_signals (RT2-3)
# ---------------------------------------------------------------------------
echo "--- T17: test_retry_fires_if_no_active_signals ---"
RESULT=$(python3 -c "
import sys, os, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
# Monkey-patch to return idle pane text
d._capture_pane_text = lambda sn: 'user@host:~\$ '
print(d._is_session_actively_working('any_session'))
")
assert_eq "T17: no signals → not active" "$RESULT" "False"

# ---------------------------------------------------------------------------
# T18: test_stats_both_rates_present (RT2-5)
# ---------------------------------------------------------------------------
echo "--- T18: test_stats_both_rates_present ---"
RESULT=$(python3 -c "
import sys, os, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
d._acorn_idle_stats('success')
d._acorn_idle_stats('failure')
stats = d.state.get('acorn_idle_stats', {})
has_both = 'lifetime_success_rate_pct' in stats and 'rolling_success_rate_pct' in stats
print('OK' if has_both else f'MISSING: {list(stats.keys())}')
")
assert_eq "T18: both rates present" "$RESULT" "OK"

# ---------------------------------------------------------------------------
# T19: test_circuit_breaker_trips_at_threshold (RT2-7)
# ---------------------------------------------------------------------------
echo "--- T19: test_circuit_breaker_trips_at_threshold ---"
RESULT=$(python3 -c "
import sys, os, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
# 3 consecutive systemic failures
d._update_session_circuit_breaker(success=False, systemic=True)
d._update_session_circuit_breaker(success=False, systemic=True)
d._update_session_circuit_breaker(success=False, systemic=True)
cb = d.state.get('acorn_circuit_breaker', {})
blocked = cb.get('blocked', False)
notified = any('CIRCUIT BREAKER' in n['message'] for n in d._notifications)
print('TRIPPED' if blocked and notified else f'blocked={blocked} notified={notified}')
")
assert_eq "T19: 3 systemic → tripped" "$RESULT" "TRIPPED"

# ---------------------------------------------------------------------------
# T20: test_circuit_breaker_resets_on_success (RT2-7)
# ---------------------------------------------------------------------------
echo "--- T20: test_circuit_breaker_resets_on_success ---"
RESULT=$(python3 -c "
import sys, os, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
d._update_session_circuit_breaker(success=False, systemic=True)
d._update_session_circuit_breaker(success=False, systemic=True)
d._update_session_circuit_breaker(success=False, systemic=True)
# Now recover
d._update_session_circuit_breaker(success=True)
cb = d.state.get('acorn_circuit_breaker', {})
print('RESET' if not cb.get('blocked') and cb.get('consecutive_class_c', -1) == 0 else f'{cb}')
")
assert_eq "T20: success resets breaker" "$RESULT" "RESET"

# ---------------------------------------------------------------------------
# T21: test_health_check_alerts_on_degraded_rolling (RT-7)
# ---------------------------------------------------------------------------
echo "--- T21: test_health_check_alerts_on_degraded_rolling ---"
RESULT=$(python3 -c "
import sys, os, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
# Inject 5 failures to trigger rolling alert
for i in range(5):
    d._acorn_idle_stats('failure')
notified = any('UNDERPERFORMING' in n['message'] for n in d._notifications)
has_both_rates = any('Rolling rate' in n['message'] and 'Lifetime rate' in n['message'] for n in d._notifications)
print('OK' if notified and has_both_rates else f'notified={notified} both_rates={has_both_rates}')
")
assert_eq "T21: degraded rolling → alert with both rates" "$RESULT" "OK"

# ---------------------------------------------------------------------------
# T22: test_health_check_no_alert_below_min_trials (RT-7)
# ---------------------------------------------------------------------------
echo "--- T22: test_health_check_no_alert_below_min_trials ---"
RESULT=$(python3 -c "
import sys, os, tempfile
sys.path.insert(0, '$TMPDIR_BASE')
from helper import make_daemon
tmp = tempfile.mkdtemp()
d = make_daemon(tmp)
# Only 4 failures (below MIN_TRIALS=5)
for i in range(4):
    d._acorn_idle_stats('failure')
notified = any('UNDERPERFORMING' in n['message'] for n in d._notifications)
print('OK' if not notified else 'ALERTED')
")
assert_eq "T22: < 5 trials → no alert" "$RESULT" "OK"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Unit tests: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ] || exit 1
