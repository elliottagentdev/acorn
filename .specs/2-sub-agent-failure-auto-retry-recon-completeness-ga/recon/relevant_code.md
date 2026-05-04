# Relevant Code: Sub-Agent Failure Auto-Retry + Recon Completeness Gate

## Primary File: `/home/agentdev/.local/bin/acorn`

Single bash file, 3690 lines total. All pipeline orchestration lives here.
The development copy (used for test sourcing) is at `/home/agentdev/projects/acorn/main/bin/acorn`.

---

## 1. Top-Level Globals and Env Var Patterns (lines 1–23)

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="acorn"
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"
LIFECYCLE_LABELS=(...)
TELEGRAM_NOTIFY_PORT="${TELEGRAM_NOTIFY_PORT:-8765}"
TELEGRAM_NOTIFY_URL="http://127.0.0.1:${TELEGRAM_NOTIFY_PORT}/notify"
```

**Pattern for new env vars:** declare at top of file with `${VAR:-default}` syntax. Examples of existing env vars:
- `PROJECTS_DIR` (line 6) — path override
- `TELEGRAM_NOTIFY_PORT` (line 9) — port override
- `FOREMAN_HOME` (used inline as `${FOREMAN_HOME:-$HOME/.foreman}` at lines 2237, 2322, 2417, 3415)
- `SESSION_NAME` (line 2467) — injected by caller
- `WATCHDOG_INTERVAL_SECONDS` (line 3374) — seconds
- `DOCTOR_FAIL` (lines 3535, 3539) — flag variable, not exported

**New env vars needed for this feature:**
- `ACORN_SUBAGENT_RETRY_BUDGET` — default `1`
- `ACORN_FAILURE_EVENT_PATH` — optional path to `.jsonl` event file

---

## 2. Error Handling Infrastructure (lines 35–37)

```bash
info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
```

These three functions are the error output primitives. All existing fatal conditions use `die`. For the halt-with-diagnostics requirement, a new function (e.g. `halt_pipeline`) should write structured output to stderr and optionally append to `ACORN_FAILURE_EVENT_PATH`, then call `die` or `exit 1`.

---

## 3. Event Emission: `notify_foreman` (lines 65–119)

```bash
notify_foreman() {
  local event_type="$1"
  local message="$2"
  local session="${3:-}"
  local extra_data="${4:-{}}"

  (
    ...
    local payload
    payload="$(jq -nc \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg event "$event_type" \
      --arg session "$session" \
      --argjson data "$extra_data" \
      '{ts: $ts, event: $event, source: "acorn", session: $session, data: $data}')"

    local http_code
    http_code=$(curl -s --max-time 3 \
      -o /dev/null -w '%{http_code}' \
      -X POST -H "Content-Type: application/json" \
      -d "$payload" \
      "http://localhost:7700/notify-foreman" 2>/dev/null) || http_code="0"

    if [[ "$http_code" != "200" ]]; then
      # falls back to notify_telegram
      ...
    fi
  ) &
  disown
}
```

`notify_foreman` is the existing JSONL-like event emission path. It fires in a background subshell and falls back to Telegram. The new `ACORN_FAILURE_EVENT_PATH` feature should NOT reuse this function — it appends to a file instead of posting to an HTTP endpoint. A new dedicated function `emit_failure_event` is needed.

---

## 4. Circuit Breaker Pattern (lines 121–140)

```bash
check_circuit_breaker() {
  local forged_url="http://localhost:7700/status"
  local response
  set +e
  response="$(curl -fsS --max-time 3 "$forged_url" 2>/dev/null)"
  local ec=$?
  set -e

  if [ $ec -ne 0 ]; then
    warn "Forged not reachable -- skipping circuit breaker check (fail-open)"
    return 0
  fi

  local blocked
  blocked="$(printf '%s' "$response" | jq -r '.acorn_circuit_breaker.blocked // false' 2>/dev/null)"
  if [ "$blocked" = "true" ]; then
    die "Acorn circuit breaker is TRIPPED ..."
  fi
  return 0
}
```

This shows the pattern for fail-open external checks (`set +e`, check ec, `set -e`, warn then return 0). The new retry logic should use the same pattern for backoff sleeps.

---

## 5. Pipeline Entry: `auto_trigger_message` (lines 26–33)

```bash
auto_trigger_message() {
  local spec_path="$1"
  local mode="${2:-full}"
  case "$mode" in
    full)  printf 'Read %s/PROMPT.md and follow ALL instructions...' ... ;;
    lite)  printf 'Read %s/PROMPT.md and follow ALL instructions...' ... ;;
    quick) printf 'Read %s/PROMPT.md and follow ALL instructions...' ... ;;
  esac
}
```

The orchestrator (a Claude tmux session) is triggered with a single message that says "follow ALL instructions in PROMPT.md". The orchestrator then reads PROMPT.md, which contains the embedded planning methodology. There is **no programmatic stage advancement** in the bash layer — it is entirely prompt-driven inside the Claude session. This is the critical architectural fact: the bash script **cannot currently intercept stage transitions** because they happen inside a tmux Claude session, not in the bash process.

---

## 6. Stage 0 Recon — Where Sub-Agents Are Launched (PROMPT.md content)

### Full pipeline: lines 717–783 (in `planning_block_full`)

Stage 0 prompt is embedded in a heredoc:
```bash
planning_block_full() {
  local spec_path="${1:-.}"
  cat <<'METHODOLOGY_EOF' | sed "s|__SPEC_PATH__|${spec_path}|g"
...
### Stage 0: Codebase Reconnaissance

YOU MUST launch 3 Task tool calls in a SINGLE message (parallel execution). Use model "opus".
...
**After all 3 complete:** Confirm all 3 files exist (__SPEC_PATH__/recon/architecture.md,
__SPEC_PATH__/recon/relevant_code.md, __SPEC_PATH__/recon/conventions.md),
then proceed to Stage 1. Do NOT read the files.
```

The "Confirm all 3 files exist" instruction at line 783 is currently **a text prompt to the orchestrator Claude** — it is not a bash check.

### Lite pipeline: lines 1187–1253 (in `planning_block_lite`)

Identical structure to full, but uses `model "sonnet"` for Stage 0.
Same trailing instruction at line 1253: "Confirm all 3 files exist".

### Quick pipeline: lines 1465–1530 (in `planning_block_quick`)

Same structure again. Trailing instruction at line 1530.

---

## 7. Expected Artifact Paths Per Stage

All artifact paths use `__SPEC_PATH__` placeholder, resolved via `sed` at runtime to the real `$spec_path` directory.

### Stage 0 (all modes)
- `__SPEC_PATH__/recon/architecture.md`
- `__SPEC_PATH__/recon/relevant_code.md`
- `__SPEC_PATH__/recon/conventions.md`

### Stage 1 (full mode) — 4 parallel drafts
- `__SPEC_PATH__/plans/draft_plan_1.md`
- `__SPEC_PATH__/plans/draft_plan_2.md`
- `__SPEC_PATH__/plans/draft_plan_3.md`
- `__SPEC_PATH__/plans/draft_plan_4.md`

### Stage 2 (full mode)
- `__SPEC_PATH__/plans/evaluation.md`

### Stage 3 (full mode)
- `__SPEC_PATH__/plans/master_plan.md`

### Stage 4 (full mode) — 4 parallel red-team
- `__SPEC_PATH__/plans/redteam_1.md`
- `__SPEC_PATH__/plans/redteam_2.md`
- `__SPEC_PATH__/plans/redteam_3.md`
- `__SPEC_PATH__/plans/redteam_4.md`

### Stage 5 (full mode) / Stage 3 (lite) / Stage 1 (quick)
- `__SPEC_PATH__/plans/SPEC.md`

### Stage 1 (lite mode)
- `__SPEC_PATH__/plans/draft.md`

### Stage 2 (lite mode)
- `__SPEC_PATH__/plans/validation.md`

---

## 8. Where Sub-Agent Artifacts Are Currently Verified

### `cmd_approve` (line 2403)
```bash
[ -f "$dir/plans/SPEC.md" ] || die "Missing final plan: $dir/plans/SPEC.md"
```
This is the **only** existing programmatic artifact check — it happens at approve time, not during pipeline execution.

### `cmd_spec_complete` (line 2445)
```bash
[ -f "$dir/plans/SPEC.md" ] || die "Missing final plan: $dir/plans/SPEC.md"
```
Same check, same timing. Both commands only verify the terminal artifact.

### `validate_prompt_md` (lines 1672–1676)
```bash
validate_prompt_md() {
  local prompt_path="$1"
  grep -q 'PLANNING METHODOLOGY — MANDATORY INSTRUCTIONS' "$prompt_path" || return 1
  return 0
}
```
Used in `cmd_create` (line 2277) to validate the generated PROMPT.md before writing it. Pattern: non-zero return on failure, caller checks with `if !`.

### `status_for_spec` (lines 1999–2037)
```bash
[ -f "$spec_path/plans/SPEC.md" ] && final_exists=1
[ -f "$spec_path/PROMPT.md" ] && prompt_exists=1
```
Uses existence checks for status display. Shows how the bash layer already queries artifact existence after the fact.

---

## 9. Session and Tmux Layer (lines 1820–1912)

```bash
start_session() {
  local repo="$1"; local slug="$2"; local spec_path="$3"; local auto_trigger="${4:-0}"
  local session_name
  session_name="$(canonical_session_name "$repo" "$slug")"
  require_cmds tmux claude
  if tmux has-session -t "$session_name" 2>/dev/null; then
    printf '%s\n%s' "tmux" "$session_name"
    return 0
  fi
  tmux new-session -d -s "$session_name" -c "$spec_path"
  if [ "$auto_trigger" -eq 1 ]; then
    tmux send-keys -t "$session_name" "claude --dangerously-skip-permissions" C-m || true
  else
    tmux send-keys -t "$session_name" "claude" C-m || true
  fi
  printf '%s\n%s' "tmux" "$session_name"
}
```

Key insight: the pipeline runs inside `claude` in a tmux session. The bash process exits after launching the session. **There is no bash process watching for stage completion**. The retry logic described in the feature must live in the orchestrator prompt instructions — not as a wrapping bash loop around a tmux session.

```bash
send_auto_trigger() {
  local session_name="$1"; local message="$2"
  (
    wait_for_claude_ready "$session_name" 30 2 || true
    tmux send-keys -t "$session_name" -l "$message"
    sleep 1
    tmux send-keys -t "$session_name" Enter
  ) &
  disown
}
```

The auto-trigger is fire-and-forget via background subshell + `disown`.

---

## 10. `planning_block_*` Functions — Where Changes Will Be Made

The three functions that generate the planning methodology text embedded in PROMPT.md:

```
planning_block_full()   lines 673–1138   (~465 lines)
planning_block_lite()   lines 1141–1416  (~276 lines)
planning_block_quick()  lines 1419–1606  (~188 lines)
```

All three share the same structural pattern:
1. A heredoc starting at `cat <<'METHODOLOGY_EOF'` with `sed "s|__SPEC_PATH__|${spec_path}|g"` piped.
2. Stage 0 instructions with 3 parallel Task agents for recon.
3. Per-stage instructions for subsequent stages.
4. An "After all N complete" block at the end of each stage directing the orchestrator to confirm file existence.
5. An "Orchestrator Context Management" section reminding the orchestrator not to read files.

**The "Confirm all 3 files exist" lines are the insertion points:**
- Full: line 783 — `**After all 3 complete:** Confirm all 3 files exist (__SPEC_PATH__/recon/...`
- Lite: line 1253 — identical
- Quick: line 1530 — identical

The feature requires changing these human-readable confirmation instructions into machine-enforced checks. Since the checks must happen at the orchestrator prompt level (Claude), the best approach is to enhance the text instructions with explicit retry-and-halt behavior.

---

## 11. `planning_block` Router (lines 662–671)

```bash
planning_block() {
  local mode="${1:-full}"
  local spec_path="${2:-.}"
  case "$mode" in
    full)  planning_block_full "$spec_path" ;;
    lite)  planning_block_lite "$spec_path" ;;
    quick) planning_block_quick "$spec_path" ;;
    *)     die "Unknown planning mode: $mode" ;;
  esac
}
```

Called from `render_prompt_md` (line 1652). This is the single routing point for all three mode variations.

---

## 12. `render_prompt_md` (lines 1621–1669)

```bash
render_prompt_md() {
  local issue_title="$1"
  local issue_body="$2"
  local issue_json="$3"
  local out_tmp="$4"
  local mode="${5:-full}"
  local spec_path="${6:-.}"
  local url_mapping_file="${7:-}"
  ...
  {
    printf '# Feature Spec: %s\n\n' "$issue_title"
    ...
    planning_block "$mode" "$spec_path"
    printf '\n\n---\n\n'
    cat <<'EOF'
## Completion Protocol
...
EOF
  } > "$out_tmp"
}
```

The spec_path is known at render time and fully resolved. Any new bash-level artifact checking function would receive this same `spec_path`.

---

## 13. `cmd_create` — Full Launch Flow (lines 2209–2350)

Key sequence:
1. Parse flags (`--no-auto`, `--lite`, `--quick`) → set `mode` variable (line 2216–2233)
2. Auth pre-flight gate (lines 2237–2242)
3. Circuit-breaker check (lines 2244–2247)
4. Fetch issue from GitHub, compute slug, create `$dir` (lines 2249–2268)
5. Render PROMPT.md if not present (lines 2269–2287)
6. Set GitHub labels (lines 2289–2292)
7. Start tmux session, fire auto-trigger (lines 2295–2328)
8. Write meta.json (line 2331)
9. Print summary (lines 2333–2348)
10. Telegram notification (line 2349)

**The pipeline runs entirely within the Claude tmux session after step 7.** The bash process does not wait or poll — it returns immediately after firing the auto-trigger.

---

## 14. File Existence Check Pattern Used in Tests

From `test_doctor.sh` (lines 73–81):
```bash
find "$spec_dir" -maxdepth 4 -type f -printf '%T@\n' 2>/dev/null \
  | sort -rn | head -1 | cut -d. -f1
```

From `validate_prompt_md` (line 1673):
```bash
grep -q 'PLANNING METHODOLOGY — MANDATORY INSTRUCTIONS' "$prompt_path" || return 1
```

From `cmd_approve` (line 2403):
```bash
[ -f "$dir/plans/SPEC.md" ] || die "Missing final plan: $dir/plans/SPEC.md"
```

These three patterns show how the codebase checks file existence and content:
1. `[ -f path ]` — existence
2. `[ -s path ]` — non-empty (size > 0)
3. `grep -q 'PATTERN' path` — header/content check

---

## 15. `write_meta_json` (lines 1948–1971)

```bash
write_meta_json() {
  local path="$1"; local repo="$2"; local issue_number="$3"
  local issue_title="$4"; local slug="$5"; local backend="$6"
  local session_name="$7"; local mode="${8:-full}"

  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  jq -n \
    --arg repo "$repo" \
    --argjson issue_number "$issue_number" \
    --arg issue_title "$issue_title" \
    --arg slug "$slug" \
    --arg created_at "$ts" \
    --arg session_backend "$backend" \
    --arg session_name "$session_name" \
    --arg mode "$mode" \
    '{repo:$repo, issue_number:$issue_number, issue_title:$issue_title, slug:$slug,
      created_at:$created_at, session_backend:$session_backend,
      session_name:$session_name, mode:$mode}' \
    > "$path"
}
```

This is the `jq -n` pattern for building structured JSON. The new `emit_failure_event` function should use the same pattern with `--arg` / `--argjson` flags and `>>` append to `ACORN_FAILURE_EVENT_PATH`.

---

## 16. `notify_foreman` JSONL Append Pattern (lines 65–119)

The existing `notify_foreman` posts to an HTTP endpoint. For the new failure event emission, we need a simpler append-to-file variant. Pseudocode for `emit_failure_event`:

```bash
emit_failure_event() {
  local slug="$1" stage="$2" agent="$3" artifact="$4"
  local retry_count="$5" halt_reason="$6"
  local event_path="${ACORN_FAILURE_EVENT_PATH:-}"
  [ -n "$event_path" ] || return 0

  local event
  event="$(jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg slug "$slug" \
    --arg stage "$stage" \
    --arg agent "$agent" \
    --arg artifact "$artifact" \
    --argjson retry_count "$retry_count" \
    --arg halt_reason "$halt_reason" \
    '{ts:$ts, slug:$slug, stage:$stage, agent:$agent,
      artifact:$artifact, retry_count:$retry_count, halt_reason:$halt_reason}')"

  printf '%s\n' "$event" >> "$event_path" 2>/dev/null || true
}
```

---

## 17. Test File Patterns and Harness

All tests live in `/home/agentdev/projects/acorn/main/test/`. Each test file follows this pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ACORN_SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/bin/acorn"

# Source acorn without triggering main()
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }
assert_eq() { ... }
assert_contains() { ... }

# Isolated temp dir
TMPDIR_BASE="$(mktemp -d)"
teardown() { rm -rf "$TMPDIR_BASE"; }
trap teardown EXIT

# Override notify_telegram to be silent in tests
notify_telegram() { :; }

# Tests...

printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
```

Key testing techniques used:
- **Source acorn in-process** via `eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"` to call functions directly
- **Mock tmux** by overriding the function or creating a fake binary in `$TMPDIR_BASE/bin/`
- **Capture stderr/stdout** via `out=$(cmd_foo ... 2>&1)`
- **Test exit codes** via `set +e; cmd; rc=$?; set -e`
- **Override helpers** like `notify_telegram() { :; }` to silence side effects
- **Behavioral assertions** via `grep -qF "pattern" "$ACORN_SCRIPT"` to verify code structure

New test file for this feature: `test/test_recon_completeness.sh`

---

## 18. Existing "After Stage" Check Instructions (Key Insertion Points)

### Full mode — Stage 0 (line 783)
```
**After all 3 complete:** Confirm all 3 files exist (__SPEC_PATH__/recon/architecture.md,
__SPEC_PATH__/recon/relevant_code.md, __SPEC_PATH__/recon/conventions.md), then proceed
to Stage 1. Do NOT read the files.
```

### Lite mode — Stage 0 (line 1253)
```
**After all 3 complete:** Confirm all 3 files exist (__SPEC_PATH__/recon/architecture.md,
__SPEC_PATH__/recon/relevant_code.md, __SPEC_PATH__/recon/conventions.md), then proceed
to Stage 1. Do NOT read the files.
```

### Quick mode — Stage 0 (line 1530)
```
**After all 3 complete:** Confirm all 3 files exist (__SPEC_PATH__/recon/architecture.md,
__SPEC_PATH__/recon/relevant_code.md, __SPEC_PATH__/recon/conventions.md), then proceed
to Stage 1. Do NOT read the files.
```

### Full mode — Orchestrator Context Management (line 1137)
```
- If a sub-agent fails, relaunch it. Do NOT do its work yourself as a fallback.
```

### Lite mode — Orchestrator Context Management (line 1415)
```
- If a sub-agent fails, relaunch it. Do NOT do its work yourself as a fallback.
```

### Quick mode — Orchestrator Context Management (line 1605)
```
- If a sub-agent fails, relaunch it. Do NOT do its work yourself as a fallback.
```

---

## 19. Architecture Decision: Prompt-Level vs. Bash-Level Checks

The current architecture means there are **two layers** where retry and completeness checks can live:

### Layer A: Inside the PROMPT.md text (prompt-level, line modifications)

The orchestrator Claude reads PROMPT.md and follows the instructions. Currently:
- "Confirm all 3 files exist" → human-readable, Claude self-verifies
- "If a sub-agent fails, relaunch it" → manual instruction, Claude may or may not follow

**Changes needed:** Rewrite these instructions to be more explicit:
1. State exactly which files must exist AND be non-empty AND contain required headers
2. Specify: if a file is missing or empty after a Task agent returns, relaunch that specific agent (up to `ACORN_SUBAGENT_RETRY_BUDGET` times, default 1), with a sleep before retry
3. Specify: if retries exhausted, write a diagnostic artifact and STOP (do not proceed to Stage 1)
4. Specify the expected headers for each recon file (e.g. `## Directory Structure` in architecture.md)

### Layer B: Bash-level post-pipeline check (in `cmd_create` or a new `cmd_validate_stage`)

A bash function that runs after the pipeline session completes to verify all expected artifacts exist. This is appropriate for the `acorn approve` gate (which already has a check) but cannot intercept mid-pipeline failures since the bash process is not polling the session.

**For this feature, Layer A (prompt-level) is the correct approach** for in-pipeline retry because:
1. The bash process exits after `send_auto_trigger`; it cannot poll tmux
2. The orchestrator Claude is the only agent that knows which sub-agent failed
3. Claude has the Task tool to relaunch sub-agents

Layer B is appropriate for:
- Pre-advancement checks in `cmd_approve` (already done)
- A new `acorn validate <repo> <slug>` command for post-hoc diagnosis
- The `emit_failure_event` call (appending to `ACORN_FAILURE_EVENT_PATH`) which can be a bash utility function called from the prompt-generated diagnostic artifact

---

## 20. Expected Section Headers for Recon Completeness Gate

From the orchestrator instructions embedded in PROMPT.md, each recon agent has specific output requirements. The required headers to validate are not explicitly listed in the current code — the "Confirm all 3 files exist" check is purely existence-based. The feature requires adding header-level validation.

**Inferred expected headers from sub-agent prompts:**

`architecture.md` — Agent A explores:
- Directory layout and project structure
- Tech stack, frameworks, languages
- Build system and deployment model
- Key entry points and main modules
- Database schemas and data layer architecture
Expected section: `## Directory Structure` (mentioned in PROMPT.md acceptance criterion)

`relevant_code.md` — Agent B identifies:
- Files/modules most likely to be modified
- Existing APIs, endpoints, interfaces
- Data models, types, schemas
Expected section: `## Files to Modify` or `## Key Functions`

`conventions.md` — Agent C documents:
- Coding style and naming conventions
- Error handling patterns
- Test framework patterns
- CI/CD configuration
Expected section: `## Coding Style` or `## Error Handling Patterns`

---

## 21. Backoff Pattern (No Existing Implementation)

There is **no existing retry or backoff loop** in the acorn bash script. The only "retry" instruction is the manual text "If a sub-agent fails, relaunch it" (lines 1137, 1415, 1605).

The new prompt text should specify the retry-with-backoff behavior to the orchestrator Claude. Example wording to embed in the planning block:

```
**Recon Completeness Gate (mandatory before Stage 1):**
After all 3 Task agents complete, validate each output file:
1. File must exist at the expected path
2. File must be non-empty (> 0 bytes)  
3. architecture.md must contain "## Directory Structure"
4. relevant_code.md must contain at least one "##" section header
5. conventions.md must contain at least one "##" section header

If any file fails validation:
- Re-launch ONLY the failed agent (do not re-run passing agents)
- Wait 30 seconds before relaunching (use a brief pause / wait instruction to sub-agent)
- Retry budget: ${ACORN_SUBAGENT_RETRY_BUDGET:-1} retry (default: 1)
- If retry budget exhausted: write diagnostics to __SPEC_PATH__/recon/HALT.md and STOP. Do NOT proceed to Stage 1.

HALT.md must contain:
- Which stage halted
- Which agent/file failed
- Expected vs. observed (file content or "file missing")
- Suggested operator action: run `acorn clean <repo> <slug>` and re-create

If ACORN_FAILURE_EVENT_PATH is set (currently: ${ACORN_FAILURE_EVENT_PATH:-unset}),
append the HALT event to that path in JSON format.
```

The `${ACORN_SUBAGENT_RETRY_BUDGET:-1}` and `${ACORN_FAILURE_EVENT_PATH:-unset}` expansions are resolved at PROMPT.md render time via `render_prompt_md` using the bash heredoc + sed mechanism.

---

## 22. HALT.md Artifact Pattern

The feature requires a diagnostic artifact on halt. The existing spec directory structure supports this:

```
$spec_path/
  PROMPT.md
  meta.json
  recon/
    architecture.md
    relevant_code.md
    conventions.md
    HALT.md          ← NEW: written by orchestrator on failure
  plans/
    SPEC.md          ← should NOT exist if pipeline halted at Stage 0
```

The presence of `recon/HALT.md` (or absence of `plans/SPEC.md`) is checkable by a new bash utility or `acorn doctor`.

---

## 23. `cmd_doctor` — Integration Point for Halt Detection (lines 3411–3557)

`cmd_doctor` currently checks session health (running vs. stalled). It could be extended to check for `HALT.md` files in spec directories and report them. The inline fallback check pattern (lines 3470–3483) shows how to check file ages without the external `hang-detect.sh`:

```bash
local newest_mtime now_epoch age_min
newest_mtime=$(find "$slug_dir" -maxdepth 4 -type f -printf '%T@\n' 2>/dev/null \
  | sort -rn | head -1 | cut -d. -f1)
```

A similar `find "$slug_dir/recon" -name "HALT.md"` check could surface halted pipelines in `acorn doctor` output.

---

## 24. Relevant Lines Summary Table

| Function/Section | File | Lines | Relevance |
|---|---|---|---|
| Global env vars | acorn | 6–10 | Add `ACORN_SUBAGENT_RETRY_BUDGET`, `ACORN_FAILURE_EVENT_PATH` |
| `info/warn/die` | acorn | 35–37 | Error output primitives; new `halt_pipeline` function |
| `notify_foreman` | acorn | 65–119 | JSONL event pattern; inspire `emit_failure_event` |
| `check_circuit_breaker` | acorn | 121–140 | fail-open external check pattern |
| `auto_trigger_message` | acorn | 26–33 | How pipeline is started |
| `planning_block_full` Stage 0 | acorn | 717–783 | Recon agent launch instructions + "Confirm" text |
| `planning_block_lite` Stage 0 | acorn | 1187–1253 | Recon agent launch instructions + "Confirm" text |
| `planning_block_quick` Stage 0 | acorn | 1465–1530 | Recon agent launch instructions + "Confirm" text |
| Orchestrator "relaunch" instructions | acorn | 1137, 1415, 1605 | Manual retry instructions to replace |
| `validate_prompt_md` | acorn | 1672–1676 | File content check pattern |
| `render_prompt_md` | acorn | 1621–1669 | Where `planning_block` is embedded into PROMPT.md |
| `planning_block` router | acorn | 662–671 | Single dispatch for all three modes |
| `start_session` | acorn | 1820–1842 | Session launch; fire-and-forget |
| `send_auto_trigger` | acorn | 1873–1885 | Pipeline trigger; disowned background |
| `write_meta_json` | acorn | 1948–1971 | jq -n JSON construction pattern |
| `status_for_spec` | acorn | 1999–2037 | Post-hoc file existence checks |
| `cmd_create` | acorn | 2209–2350 | Full launch flow |
| `cmd_approve` artifact check | acorn | 2403 | Existing SPEC.md check pattern |
| `cmd_spec_complete` artifact check | acorn | 2445 | Existing SPEC.md check pattern |
| `cmd_doctor` | acorn | 3411–3557 | Session health; extend for HALT.md detection |
| `DOCTOR_FAIL` flag pattern | acorn | 3535, 3539 | Accumulating failure flag pattern |
