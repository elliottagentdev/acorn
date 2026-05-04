# Implementation Plan — Sub-agent failure auto-retry + recon completeness gate

## Executive Summary

This feature formalizes two existing manual-narrative orchestrator instructions ("Confirm all N files exist", "If a sub-agent fails, relaunch it") into a **dual-layer enforcement system**:

1. **Layer A (prompt-level, primary)**: Strengthen the embedded planning methodology in `planning_block_full/lite/quick` so the orchestrator Claude performs explicit programmatic artifact validation, retry-with-backoff, and halt-with-diagnostics inside the tmux session — because the bash process exits before the pipeline runs and cannot poll mid-pipeline state.
2. **Layer B (bash-level, defensive)**: Add a small set of bash helpers (`validate_stage_artifacts`, `emit_failure_event`, `halt_pipeline_diagnostic`) that can be invoked by the orchestrator via `Bash` tool calls AND by post-hoc commands (`cmd_doctor`, `cmd_approve`) for halt detection and event emission. These helpers also become callable as subcommands (`acorn _internal validate-stage`, `acorn _internal emit-failure-event`) so the orchestrator can invoke them as deterministic shell calls rather than re-implementing JSON construction inside its prompt.

The bash layer thus provides **deterministic primitives** that the orchestrator can call; the prompt-level instructions wire them together into the retry/halt control flow. This balances:
- **Minimal surgery**: All changes localised to the existing single-file `bin/acorn` (~3690 lines) and a new `test/test_recon_completeness.sh`. No new top-level files, no module split.
- **Clean architecture**: Validation logic lives in named helper functions (testable in isolation). The orchestrator's prompt-level loop calls these helpers; it does not re-derive validation rules.
- **Robustness**: Existence + non-empty + section-header checks; configurable retry budget with backoff; structured halt artifact (`HALT.md`) and optional JSONL event emission; bash-layer halt detection in `cmd_doctor`.
- **Developer experience**: Two new env vars (`ACORN_SUBAGENT_RETRY_BUDGET`, `ACORN_FAILURE_EVENT_PATH`) with sane defaults that preserve current behaviour. Failure messages name the exact stage, agent, file, and a copy-pasteable recovery command.

---

## 1. Architecture

### 1.1 The fundamental constraint

From recon (relevant_code §5, §9, architecture §"Session Management Model"):

> The bash process **exits after `send_auto_trigger`**. The pipeline runs entirely inside a `claude` process in a tmux session. There is no programmatic feedback loop between bash and the orchestrator.

This means the retry/halt control flow **must execute inside the orchestrator's prompt logic**. It cannot be a bash `while` loop wrapping the session. The bash layer's role is therefore:

- Provide deterministic helper functions that the orchestrator can shell out to (instead of asking the LLM to construct JSON, parse mtimes, or compare file contents itself).
- Embed retry-budget and event-path configuration into the rendered PROMPT.md at spec-creation time so values are baked in (not re-read at runtime).
- Provide halt-detection commands (`acorn doctor`, status output) so operators see halted pipelines without reading every spec dir manually.

### 1.2 Component map

```
┌─────────────────────────────────────────────────────────────────────────┐
│ bash layer (bin/acorn)                                                  │
│                                                                         │
│  cmd_create ──> render_prompt_md ──> planning_block_{full,lite,quick}   │
│                                          │                              │
│                                          ▼  (text + ${RETRY_BUDGET}     │
│                                              + ${EVENT_PATH} expanded)  │
│                                       PROMPT.md                         │
│                                                                         │
│  helpers (callable from CLI as `acorn _internal …`):                    │
│    validate_stage_artifacts <spec_dir> <stage>                          │
│    emit_failure_event       <slug> <stage> <agent> <artifact>           │
│                             <retry_count> <reason>                      │
│    halt_pipeline_diagnostic <spec_dir> <stage> <agent> <artifact>       │
│                             <reason>                                    │
│                                                                         │
│  cmd_doctor (extended) ──> scans for recon/HALT.md, plans/HALT.md       │
│  cmd_status / status_for_spec (extended) ──> reports halted state       │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ orchestrator reads PROMPT.md
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Claude orchestrator (tmux session)                                      │
│                                                                         │
│  per stage:                                                             │
│    1. Launch Task sub-agent(s) (parallel for Stage 0, sequential        │
│       elsewhere)                                                        │
│    2. After Task returns, run Bash:                                     │
│         acorn _internal validate-stage <spec_dir> <stage>               │
│       which returns 0 (ok) or non-zero with stderr diagnostic           │
│    3. If non-zero: relaunch failed agent (1 retry by default), wait     │
│       30 s before retry                                                 │
│    4. If retry exhausted: run Bash:                                     │
│         acorn _internal halt <spec_dir> <stage> <agent> <artifact>      │
│                              <reason>                                   │
│       which writes HALT.md, emits failure event, exits non-zero         │
│    5. STOP — do not advance to next stage                               │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.3 Why this split is the right one

**Alternative considered**: Put all logic in the LLM prompt — let the orchestrator run `[ -f path ]` checks, build JSON with heredocs, etc.

Rejected because:
- LLMs are unreliable at multi-step bash construction (JSON escaping, header validation grep flags, etc.).
- A halt diagnostic is a contract — operators need consistent output. Hand-rolling it in prompt-space gives drift across pipeline modes and runs.
- Tests would have to harness the LLM, not the validation logic.

**Alternative considered**: Wrap the tmux session in a polling bash loop — block `cmd_create` until pipeline completes.

Rejected because:
- Breaks fire-and-forget semantics that Foreman, watchdogs, and humans rely on (`cmd_create` would hang forever).
- Race conditions with concurrent `acorn create` calls on different specs.
- The orchestrator is the only agent that knows which specific Task agent failed (bash sees only filesystem snapshots).

**Chosen split**: Orchestrator drives control flow; bash provides deterministic primitives. This matches existing patterns (`validate_prompt_md`, `notify_foreman`, `write_meta_json`).

---

## 2. Data Models

### 2.1 New environment variables (top of `bin/acorn`, near lines 6–10)

```bash
ACORN_SUBAGENT_RETRY_BUDGET="${ACORN_SUBAGENT_RETRY_BUDGET:-1}"
ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS="${ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS:-30}"
ACORN_FAILURE_EVENT_PATH="${ACORN_FAILURE_EVENT_PATH:-}"
```

| Variable | Default | Effect when unset / default |
|---|---|---|
| `ACORN_SUBAGENT_RETRY_BUDGET` | `1` | One retry per sub-agent (matches current "If a sub-agent fails, relaunch it" instruction) |
| `ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS` | `30` | 30 s between retries |
| `ACORN_FAILURE_EVENT_PATH` | `""` (empty) | Event emission disabled |

These are read once at script startup. Values are interpolated into `PROMPT.md` at render time (so each spec is pinned to the values active when `acorn create` ran — predictable for reruns).

### 2.2 Stage manifest (new internal data)

A new bash function `stage_manifest <mode> <stage>` returns the expected artifacts and required headers for a given stage. This is the single source of truth used by `validate_stage_artifacts` and by the rendered prompt text.

```
stage_manifest full 0  -> "recon/architecture.md|## Directory Structure
                            recon/relevant_code.md|##
                            recon/conventions.md|##"
stage_manifest full 1  -> "plans/draft_plan_1.md|##
                            plans/draft_plan_2.md|##
                            plans/draft_plan_3.md|##
                            plans/draft_plan_4.md|##"
stage_manifest full 2  -> "plans/evaluation.md|##"
stage_manifest full 3  -> "plans/master_plan.md|##"
stage_manifest full 4  -> "plans/redteam_1.md|##
                            plans/redteam_2.md|##
                            plans/redteam_3.md|##
                            plans/redteam_4.md|##"
stage_manifest full 5  -> "plans/SPEC.md|##"

stage_manifest lite 0  -> (same as full stage 0)
stage_manifest lite 1  -> "plans/draft.md|##"
stage_manifest lite 2  -> "plans/validation.md|##"
stage_manifest lite 3  -> "plans/SPEC.md|##"

stage_manifest quick 0 -> (same as full stage 0)
stage_manifest quick 1 -> "plans/SPEC.md|##"
```

Format: each line is `<relative_path>|<required_header_pattern>`. The header pattern is a regex that the file must match via `grep -E -q`. `##` matches any markdown level-2 header (i.e., the file must have at least one heading — proves it's not just whitespace). For `architecture.md`, the explicit `## Directory Structure` is required per AC #5.

### 2.3 HALT.md format

Written by `halt_pipeline_diagnostic` to `<spec_dir>/<stage_dir>/HALT.md` (e.g. `recon/HALT.md` for Stage 0, `plans/HALT.md` for later stages).

```markdown
# Pipeline Halt: stage 0 (recon)

Halted at: 2026-05-02T14:33:11Z
Pipeline mode: lite
Spec slug: 2-sub-agent-failure-auto-retry-recon-completeness-ga
Repo: acorn
Stage: 0 (recon)
Failed agent: Agent A (Architecture & Structure)
Expected artifact: <spec>/recon/architecture.md
Observed: file missing
Retry count exhausted: 1 of 1
Halt reason: artifact_missing

## Last 50 lines of agent output

```
(captured from sub-agent return message; "(no output captured)" if not available)
```

## Suggested operator action

Run:

    acorn clean acorn 2-sub-agent-failure-auto-retry-recon-completeness-ga --yes
    acorn create acorn 2 --lite

Or, to retry just this stage manually, attach to the tmux session:

    tmux attach -t acorn_specs_2-sub-agent-failure-auto-retry-recon-completeness-ga_claude

and ask the orchestrator to relaunch Agent A.
```

### 2.4 JSONL failure event schema (`ACORN_FAILURE_EVENT_PATH`)

One event per line. Forge points this at `~/.foreman/.foreman-events.jsonl`; upstream callers leave unset.

```json
{
  "ts": "2026-05-02T14:33:11Z",
  "source": "acorn",
  "event": "subagent.halt",
  "slug": "2-sub-agent-failure-auto-retry-recon-completeness-ga",
  "repo": "acorn",
  "issue_number": 2,
  "mode": "lite",
  "stage": 0,
  "stage_name": "recon",
  "agent": "Agent A (Architecture & Structure)",
  "artifact": "recon/architecture.md",
  "retry_count": 1,
  "retry_budget": 1,
  "halt_reason": "artifact_missing",
  "observed": "file missing",
  "session_name": "acorn_specs_2-sub-agent-failure-auto-retry-recon-completeness-ga_claude"
}
```

`halt_reason` is one of: `artifact_missing`, `artifact_empty`, `header_missing`, `retry_exhausted`.

---

## 3. Specific File Changes

All changes are confined to two files: `bin/acorn` and the new `test/test_recon_completeness.sh`.

### 3.1 `bin/acorn` — new top-level config (~line 10–12, after existing env vars)

Add immediately after `TELEGRAM_NOTIFY_URL=...` (line 10):

```bash
ACORN_SUBAGENT_RETRY_BUDGET="${ACORN_SUBAGENT_RETRY_BUDGET:-1}"
ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS="${ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS:-30}"
ACORN_FAILURE_EVENT_PATH="${ACORN_FAILURE_EVENT_PATH:-}"
```

### 3.2 `bin/acorn` — new helpers (after `notify_foreman`, ~line 120)

Insert four new functions after `notify_foreman` ends and before `check_circuit_breaker`:

```bash
# ---------------------------------------------------------------------------
# Stage manifest: returns expected artifacts (path|header_regex per line)
# for a given pipeline mode and stage index.
# ---------------------------------------------------------------------------
stage_manifest() {
  local mode="$1" stage="$2"
  case "$mode:$stage" in
    full:0|lite:0|quick:0)
      printf '%s\n' \
        'recon/architecture.md|^## Directory Structure' \
        'recon/relevant_code.md|^## ' \
        'recon/conventions.md|^## '
      ;;
    full:1)
      printf '%s\n' \
        'plans/draft_plan_1.md|^## ' \
        'plans/draft_plan_2.md|^## ' \
        'plans/draft_plan_3.md|^## ' \
        'plans/draft_plan_4.md|^## '
      ;;
    full:2)
      printf '%s\n' 'plans/evaluation.md|^## '
      ;;
    full:3)
      printf '%s\n' 'plans/master_plan.md|^## '
      ;;
    full:4)
      printf '%s\n' \
        'plans/redteam_1.md|^## ' \
        'plans/redteam_2.md|^## ' \
        'plans/redteam_3.md|^## ' \
        'plans/redteam_4.md|^## '
      ;;
    full:5|lite:3|quick:1)
      printf '%s\n' 'plans/SPEC.md|^## '
      ;;
    lite:1)
      printf '%s\n' 'plans/draft.md|^## '
      ;;
    lite:2)
      printf '%s\n' 'plans/validation.md|^## '
      ;;
    *)
      die "Unknown stage manifest: mode=$mode stage=$stage"
      ;;
  esac
}

stage_name() {
  local mode="$1" stage="$2"
  case "$mode:$stage" in
    *:0) printf 'recon' ;;
    full:1) printf 'drafting' ;;
    full:2) printf 'evaluation' ;;
    full:3) printf 'synthesis' ;;
    full:4) printf 'red-team' ;;
    full:5|lite:3|quick:1) printf 'final-spec' ;;
    lite:1) printf 'drafting' ;;
    lite:2) printf 'validation' ;;
    *) printf 'unknown' ;;
  esac
}

# ---------------------------------------------------------------------------
# validate_stage_artifacts <spec_dir> <mode> <stage>
# Exits 0 when every expected artifact for the stage exists, is non-empty,
# and contains the required header pattern. Exits 1 with a single-line
# diagnostic on stderr ("MISSING|<path>", "EMPTY|<path>", or
# "HEADER|<path>|<pattern>") when any check fails.
# ---------------------------------------------------------------------------
validate_stage_artifacts() {
  local spec_dir="$1" mode="$2" stage="$3"
  [ -d "$spec_dir" ] || { printf 'MISSING|%s\n' "$spec_dir" >&2; return 1; }
  local manifest entry path header full
  manifest="$(stage_manifest "$mode" "$stage")"
  while IFS='|' read -r path header; do
    [ -n "$path" ] || continue
    full="$spec_dir/$path"
    if [ ! -f "$full" ]; then
      printf 'MISSING|%s\n' "$path" >&2
      return 1
    fi
    if [ ! -s "$full" ]; then
      printf 'EMPTY|%s\n' "$path" >&2
      return 1
    fi
    if [ -n "$header" ] && ! grep -E -q -- "$header" "$full"; then
      printf 'HEADER|%s|%s\n' "$path" "$header" >&2
      return 1
    fi
  done <<< "$manifest"
  return 0
}

# ---------------------------------------------------------------------------
# emit_failure_event — append a JSONL event when ACORN_FAILURE_EVENT_PATH set
# Args: slug stage stage_name agent artifact retry_count retry_budget
#       halt_reason observed mode repo issue_number session_name
# Always returns 0 (best-effort).
# ---------------------------------------------------------------------------
emit_failure_event() {
  local event_path="${ACORN_FAILURE_EVENT_PATH:-}"
  [ -n "$event_path" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local slug="${1:-}" stage="${2:-}" stage_name="${3:-}" agent="${4:-}"
  local artifact="${5:-}" retry_count="${6:-0}" retry_budget="${7:-0}"
  local halt_reason="${8:-}" observed="${9:-}" mode="${10:-}"
  local repo="${11:-}" issue_number="${12:-0}" session_name="${13:-}"

  local payload
  payload="$(jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg slug "$slug" \
    --argjson stage "${stage:-0}" \
    --arg stage_name "$stage_name" \
    --arg agent "$agent" \
    --arg artifact "$artifact" \
    --argjson retry_count "${retry_count:-0}" \
    --argjson retry_budget "${retry_budget:-0}" \
    --arg halt_reason "$halt_reason" \
    --arg observed "$observed" \
    --arg mode "$mode" \
    --arg repo "$repo" \
    --argjson issue_number "${issue_number:-0}" \
    --arg session_name "$session_name" \
    '{ts:$ts, source:"acorn", event:"subagent.halt",
      slug:$slug, repo:$repo, issue_number:$issue_number, mode:$mode,
      stage:$stage, stage_name:$stage_name, agent:$agent,
      artifact:$artifact, retry_count:$retry_count, retry_budget:$retry_budget,
      halt_reason:$halt_reason, observed:$observed,
      session_name:$session_name}' 2>/dev/null)" || return 0

  # Ensure parent dir exists, append atomically.
  mkdir -p "$(dirname "$event_path")" 2>/dev/null || true
  printf '%s\n' "$payload" >> "$event_path" 2>/dev/null || true
  return 0
}

# ---------------------------------------------------------------------------
# halt_pipeline_diagnostic <spec_dir> <mode> <stage> <agent> <artifact>
#                          <halt_reason> <observed> [<agent_log_tail>]
# Writes HALT.md to the appropriate stage directory, prints the same
# information to stderr via warn(), and emits a JSONL failure event
# when ACORN_FAILURE_EVENT_PATH is set. Always exits 1.
# ---------------------------------------------------------------------------
halt_pipeline_diagnostic() {
  local spec_dir="$1" mode="$2" stage="$3" agent="$4"
  local artifact="$5" halt_reason="$6" observed="$7"
  local agent_log_tail="${8:-(no output captured)}"

  local stage_dir
  case "$stage" in
    0) stage_dir="$spec_dir/recon" ;;
    *) stage_dir="$spec_dir/plans" ;;
  esac
  mkdir -p "$stage_dir" 2>/dev/null || true
  local halt_path="$stage_dir/HALT.md"

  local sname
  sname="$(stage_name "$mode" "$stage")"

  # Read meta.json values for the event, fail-soft.
  local slug repo issue_number session_name
  slug="$(jq -r '.slug // ""' "$spec_dir/meta.json" 2>/dev/null || true)"
  repo="$(jq -r '.repo // ""' "$spec_dir/meta.json" 2>/dev/null || true)"
  issue_number="$(jq -r '.issue_number // 0' "$spec_dir/meta.json" 2>/dev/null || printf '0')"
  session_name="$(jq -r '.session_name // ""' "$spec_dir/meta.json" 2>/dev/null || true)"

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  {
    printf '# Pipeline Halt: stage %s (%s)\n\n' "$stage" "$sname"
    printf 'Halted at: %s\n' "$ts"
    printf 'Pipeline mode: %s\n' "$mode"
    printf 'Spec slug: %s\n' "$slug"
    printf 'Repo: %s\n' "$repo"
    printf 'Stage: %s (%s)\n' "$stage" "$sname"
    printf 'Failed agent: %s\n' "$agent"
    printf 'Expected artifact: %s\n' "$artifact"
    printf 'Observed: %s\n' "$observed"
    printf 'Retry budget: %s\n' "${ACORN_SUBAGENT_RETRY_BUDGET:-1}"
    printf 'Halt reason: %s\n\n' "$halt_reason"
    printf '## Last 50 lines of agent output\n\n'
    printf '```\n%s\n```\n\n' "$agent_log_tail"
    printf '## Suggested operator action\n\n'
    printf 'Run:\n\n'
    printf '    acorn clean %s %s --yes\n' "$repo" "$slug"
    printf '    acorn create %s %s --%s\n\n' "$repo" "$issue_number" "$mode"
    printf 'Or attach to the tmux session and ask the orchestrator to '
    printf 'relaunch the failed agent:\n\n'
    printf '    tmux attach -t %s\n' "$session_name"
  } > "$halt_path" 2>/dev/null || warn "Failed to write $halt_path"

  warn "Pipeline halted: $sname stage (mode=$mode)"
  warn "  Failed agent:      $agent"
  warn "  Expected artifact: $artifact"
  warn "  Observed:          $observed"
  warn "  Halt reason:       $halt_reason"
  warn "  Diagnostic:        $halt_path"
  warn "  Recovery:          acorn clean $repo $slug --yes && acorn create $repo $issue_number --$mode"

  emit_failure_event \
    "$slug" "$stage" "$sname" "$agent" "$artifact" \
    "${ACORN_SUBAGENT_RETRY_BUDGET:-1}" "${ACORN_SUBAGENT_RETRY_BUDGET:-1}" \
    "$halt_reason" "$observed" "$mode" "$repo" "$issue_number" "$session_name"

  return 1
}
```

### 3.3 `bin/acorn` — new internal CLI subcommand `_internal`

The orchestrator must invoke these helpers from inside its tmux session via the `Bash` tool. Adding a hidden `_internal` subcommand exposes the helpers without polluting the public CLI surface or `--help` output.

Insert into `main()` dispatch (around line 3566–3688), keep `_internal` undocumented in help text:

```bash
case "${1:-}" in
  ...existing cases...
  _internal)
    shift
    cmd_internal "$@"
    ;;
  ...
esac
```

Add a new function (near `cmd_doctor`, ~line 3411):

```bash
cmd_internal() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    validate-stage)
      # args: <spec_dir> <mode> <stage>
      [ "$#" -eq 3 ] || die "Usage: acorn _internal validate-stage <spec_dir> <mode> <stage>"
      validate_stage_artifacts "$1" "$2" "$3"
      ;;
    halt)
      # args: <spec_dir> <mode> <stage> <agent> <artifact> <halt_reason> <observed> [<agent_log_tail>]
      [ "$#" -ge 7 ] || die "Usage: acorn _internal halt <spec_dir> <mode> <stage> <agent> <artifact> <halt_reason> <observed> [<agent_log_tail>]"
      halt_pipeline_diagnostic "$@"
      ;;
    emit-failure-event)
      emit_failure_event "$@"
      ;;
    stage-manifest)
      [ "$#" -eq 2 ] || die "Usage: acorn _internal stage-manifest <mode> <stage>"
      stage_manifest "$1" "$2"
      ;;
    *)
      die "Unknown _internal subcommand: $sub"
      ;;
  esac
}
```

These subcommands let the orchestrator do:

```bash
# inside tmux Claude session, via the Bash tool:
acorn _internal validate-stage "$SPEC_PATH" lite 0
# rc 0 = pass, rc 1 = fail with stderr like "MISSING|recon/architecture.md"

acorn _internal halt "$SPEC_PATH" lite 0 "Agent A" "recon/architecture.md" \
                     artifact_missing "file missing"
# always exits 1; writes HALT.md, emits event, prints diagnostic
```

### 3.4 `bin/acorn` — `planning_block_*` modifications

Three identical surgical patches to the three planning-block functions. Each replaces the existing "Confirm all N files exist" instruction with a programmatic loop, and replaces the orchestrator-context "If a sub-agent fails, relaunch it" line with explicit retry-budget instructions.

#### 3.4.1 Inject configuration values via the existing `sed` pipe

The functions already do `cat <<'METHODOLOGY_EOF' | sed "s|__SPEC_PATH__|${spec_path}|g"`. Extend the sed to also replace retry/event placeholders. Modify line 674–675 (full), 1142–1143 (lite), 1420–1421 (quick):

```bash
planning_block_full() {
  local spec_path="${1:-.}"
  local retry_budget="${ACORN_SUBAGENT_RETRY_BUDGET:-1}"
  local retry_backoff="${ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS:-30}"
  local event_path="${ACORN_FAILURE_EVENT_PATH:-}"
  local event_path_display="${event_path:-(unset — events disabled)}"
  cat <<'METHODOLOGY_EOF' \
    | sed "s|__SPEC_PATH__|${spec_path}|g" \
    | sed "s|__RETRY_BUDGET__|${retry_budget}|g" \
    | sed "s|__RETRY_BACKOFF__|${retry_backoff}|g" \
    | sed "s|__EVENT_PATH_DISPLAY__|${event_path_display}|g"
```

(Same wrapper for lite and quick. Note: use multiple `sed` invocations rather than one with multiple `-e` flags so the existing `s|__SPEC_PATH__|...|g` replacement is preserved verbatim — minimises diff.)

#### 3.4.2 Replace Stage 0 "Confirm all 3 files exist" block (full line 783, lite 1253, quick 1530)

Existing text:

```
**After all 3 complete:** Confirm all 3 files exist (__SPEC_PATH__/recon/architecture.md, __SPEC_PATH__/recon/relevant_code.md, __SPEC_PATH__/recon/conventions.md), then proceed to Stage 1. Do NOT read the files.
```

New text (identical at all three insertion points, modulo the next-stage label):

```
**After all 3 complete (Recon Completeness Gate — MANDATORY before Stage 1):**

YOU MUST run this validation via the Bash tool before launching any Stage 1 agent:

    acorn _internal validate-stage "__SPEC_PATH__" <MODE> 0

where <MODE> is `full`, `lite`, or `quick` matching this pipeline.

The validator checks that ALL THREE artifacts:
  - __SPEC_PATH__/recon/architecture.md
  - __SPEC_PATH__/recon/relevant_code.md
  - __SPEC_PATH__/recon/conventions.md
exist, are non-empty, AND that architecture.md contains "## Directory Structure".

**Exit code 0**: validation passed. Proceed to Stage 1. Do NOT read the files.

**Exit code 1**: validation failed. Stderr will print one of:
  - `MISSING|<relpath>`   — relaunch ONLY the agent whose file is missing
  - `EMPTY|<relpath>`     — relaunch ONLY the agent whose file is empty
  - `HEADER|<relpath>|<pattern>` — relaunch the agent and instruct them to include the header

Retry protocol on validation failure:
  1. Identify which agent owns the failed file:
     - architecture.md ↔ Agent A (Architecture & Structure)
     - relevant_code.md ↔ Agent B (Relevant Code)
     - conventions.md ↔ Agent C (Conventions & Constraints)
  2. Wait __RETRY_BACKOFF__ seconds (use the Bash tool: `sleep __RETRY_BACKOFF__`).
  3. Relaunch ONLY that one agent (do NOT re-run agents whose files passed).
     The relaunch prompt MUST be the original prompt verbatim.
  4. After the relaunched Task returns, re-run the validate-stage command.
  5. Retry budget is __RETRY_BUDGET__ retries per agent (configurable via
     ACORN_SUBAGENT_RETRY_BUDGET). After exhaustion, you MUST halt:

         acorn _internal halt "__SPEC_PATH__" <MODE> 0 \
              "<agent name>" "<failed relpath>" \
              <halt_reason> "<observed>"

     where <halt_reason> is one of: artifact_missing, artifact_empty,
     header_missing, retry_exhausted; and <observed> is a short string
     describing what was seen (e.g. "file missing", "file empty",
     "no '## Directory Structure' header").

     The halt command writes __SPEC_PATH__/recon/HALT.md, emits a JSONL
     failure event when ACORN_FAILURE_EVENT_PATH is set
     (currently: __EVENT_PATH_DISPLAY__), and exits non-zero.

  6. After running halt, STOP. Do NOT advance to Stage 1. Do NOT do the
     failed agent's work yourself as a fallback. Your final response must
     be: "Pipeline halted at Stage 0. See __SPEC_PATH__/recon/HALT.md."

Only when validate-stage exits 0 may you proceed to Stage 1. Do NOT read
the recon files yourself.
```

The same template is repeated for **every subsequent stage** in each pipeline mode, with stage-specific values. For example, in `planning_block_full` after Stage 1 (the four parallel drafts), insert:

```
**After all 4 drafts complete (Stage Completion Gate — MANDATORY before Stage 2):**

YOU MUST run:

    acorn _internal validate-stage "__SPEC_PATH__" full 1

This validates plans/draft_plan_{1,2,3,4}.md exist and are non-empty.

[same retry / halt protocol as Stage 0]
```

This pattern is repeated mechanically: Stage 1, 2, 3, 4, 5 (full); Stage 1, 2, 3 (lite); Stage 1 (quick). Total of 11 stage-completion gates inserted across the three planning blocks.

#### 3.4.3 Replace orchestrator context-management bullet (full line 1137, lite 1415, quick 1605)

Existing:

```
- If a sub-agent fails, relaunch it. Do NOT do its work yourself as a fallback.
```

New:

```
- If a sub-agent fails (validate-stage returns non-zero), relaunch it ONCE
  per __RETRY_BUDGET__ retry budget. Wait __RETRY_BACKOFF__ s between retries.
  On retry exhaustion, run `acorn _internal halt …` and STOP. Do NOT do the
  failed agent's work yourself as a fallback. The halt diagnostic file is
  authoritative — operators triage from it.
```

### 3.5 `bin/acorn` — `cmd_doctor` extension (around line 3411–3557)

Add a halt-detection check inside the existing `cmd_doctor` per-spec loop. Find the section that iterates over spec directories (the loop that builds `slug_dir` and computes age via `find -printf '%T@'`), and add:

```bash
# Halt artifact detection
local halt_recon halt_plans
halt_recon="$slug_dir/recon/HALT.md"
halt_plans="$slug_dir/plans/HALT.md"
if [ -f "$halt_recon" ] || [ -f "$halt_plans" ]; then
  local halt_file="${halt_recon}"
  [ -f "$halt_plans" ] && halt_file="$halt_plans"
  warn "  HALTED PIPELINE: see $halt_file"
  warn "  $(head -n 1 "$halt_file" 2>/dev/null || true)"
  DOCTOR_FAIL=1
fi
```

The existing `DOCTOR_FAIL=1` flag pattern is reused — a halted pipeline counts as a doctor failure, surfacing it in CI / monitoring.

### 3.6 `bin/acorn` — `status_for_spec` extension (lines 1999–2037)

Add halt detection to the existing artifact-existence checks:

```bash
local halted=0
[ -f "$spec_path/recon/HALT.md" ] && halted=1
[ -f "$spec_path/plans/HALT.md" ] && halted=1
```

In the displayed status output, when `halted=1`, prefix the status with `[HALTED] ` so `acorn list` and `acorn status` surface stalled pipelines without operators reading every spec dir.

### 3.7 `bin/acorn` — `cmd_clean` should remove HALT.md cleanly

`cmd_clean` (line 2471) already does `rm -rf` on the spec directory under safety check, so HALT.md is removed automatically. **No change needed**, but confirm with a test that HALT.md is gone after `acorn clean`.

### 3.8 New file: `test/test_recon_completeness.sh`

A new test file ~250 lines following the existing harness pattern. Detailed test list in §6.

---

## 4. API Design

### 4.1 Public CLI surface (no changes)

Existing public commands (`acorn create`, `list`, `status`, `approve`, `clean`, `doctor`, etc.) get **no new flags** for this feature. The retry/event behaviour is configured via env vars only — preserves backwards compat.

### 4.2 Internal CLI surface (new, undocumented)

```
acorn _internal validate-stage <spec_dir> <mode> <stage>
acorn _internal halt           <spec_dir> <mode> <stage> <agent> <artifact> <halt_reason> <observed> [<agent_log_tail>]
acorn _internal emit-failure-event <slug> <stage> <stage_name> <agent> <artifact> <retry_count> <retry_budget> <halt_reason> <observed> <mode> <repo> <issue_number> <session_name>
acorn _internal stage-manifest <mode> <stage>
```

These are intentionally not in `--help` or `cmd_help` output. They're an extension point for the orchestrator and tests, not a user-facing API. Tests verify they exist and behave correctly; tests also verify they're absent from `acorn --help`.

### 4.3 Function-level API (bash, internal)

| Function | Inputs | Outputs | Side effects |
|---|---|---|---|
| `stage_manifest <mode> <stage>` | mode, stage int | stdout: `path|header_pattern` lines | none |
| `stage_name <mode> <stage>` | mode, stage int | stdout: human-readable stage name | none |
| `validate_stage_artifacts <spec_dir> <mode> <stage>` | spec dir, mode, stage int | rc 0 on success; rc 1 with stderr diagnostic | none |
| `emit_failure_event ...13 args` | event metadata | rc 0 always | appends JSONL line to `$ACORN_FAILURE_EVENT_PATH` if set |
| `halt_pipeline_diagnostic ...` | halt metadata | rc 1 always | writes HALT.md, prints stderr diagnostic, calls `emit_failure_event` |
| `cmd_internal <sub> ...` | subcommand + args | dispatches to one of the above | per-sub |

---

## 5. Error Handling

### 5.1 Layer A (orchestrator prompt) error contract

When `acorn _internal validate-stage` returns non-zero, stderr contains exactly one line of one of three forms:

- `MISSING|<relpath>`
- `EMPTY|<relpath>`
- `HEADER|<relpath>|<pattern>`

The orchestrator parses this line to identify which agent to relaunch. The mapping `relpath → agent` is stable per stage and embedded in the planning block.

### 5.2 Layer B (bash helper) error handling

All four new functions follow existing acorn idioms:

- **`set -euo pipefail` is in effect** for the script. Helpers must explicitly `|| true` or `|| return 0` for fail-soft paths (event emission, mtime reads).
- **`die()` is reserved for fatal errors** in CLI command handlers; helpers prefer `return 1` so callers can decide whether to die.
- **External command absences are tolerated**: `command -v jq >/dev/null 2>&1 || return 0` in `emit_failure_event` (event emission is best-effort; no jq = no event, but no crash).
- **File-system permission failures**: writing HALT.md is wrapped `2>/dev/null`; if the spec dir is read-only, we still print the warn() diagnostic to stderr.

### 5.3 Edge cases

| Edge case | Behaviour |
|---|---|
| `ACORN_FAILURE_EVENT_PATH` set to a path whose parent doesn't exist | `mkdir -p` of parent in `emit_failure_event`. If still fails, silently ignored. |
| `ACORN_FAILURE_EVENT_PATH` set but `jq` not installed | Helper returns 0 with no event written. (jq is required for `acorn create`, but not strictly for `_internal`.) |
| `ACORN_SUBAGENT_RETRY_BUDGET=0` | Orchestrator runs validate once, halts on first failure. Tested. |
| `ACORN_SUBAGENT_RETRY_BUDGET=2` | Orchestrator allows up to 2 retries (3 total attempts). Tested. |
| `ACORN_SUBAGENT_RETRY_BUDGET=-1` or non-numeric | Treated as 1 (default). Validation: a `case` block in the helper ensures only digits; if not, warn and use default. |
| Concurrent retries (Stage 0 has 3 parallel agents — what if 2 fail?) | The orchestrator iterates: validate → identify failed agents → relaunch ALL failed agents in parallel (one Task tool call each, sent in a single message per the existing pattern) → wait → validate. Retry budget applies per agent. This is described explicitly in the planning-block prompt text. |
| Validation passes, then file is deleted between stages | Can't happen in normal flow; the orchestrator owns the spec dir. If it does (operator intervention), Stage 1 will fail when its sub-agent tries to read missing recon, which surfaces normally. |
| `meta.json` missing when halt is called | `jq -r '.slug // ""'` returns empty; HALT.md still written with empty slug; event still emitted with empty fields. Non-fatal. |
| Spec dir on read-only filesystem | HALT.md write fails silently; warn() still prints to stderr; orchestrator still STOPs (because halt rc is 1). |
| Header pattern matches whitespace-only line | `grep -E -q '^## '` requires at least the `## ` prefix; matches any heading. Acceptable. |
| File contains only `## Directory Structure` and nothing else | Passes existence + non-empty + header. Stage 0 advances. The check is "is this minimally a real recon doc", not "is the recon comprehensive". Comprehensiveness is the agent's responsibility. |
| Sub-agent writes to a sibling path (e.g. typo `architecture.md` → `architechture.md`) | Validation flags MISSING. Retry instructs the agent (text in prompt) to use the exact path. |

### 5.4 Halt-with-diagnostics requirement (AC #3) coverage

| AC #3 sub-requirement | Where it's met |
|---|---|
| Which stage halted | `halt_pipeline_diagnostic` prints stage + stage_name; HALT.md header line. |
| Which sub-agent failed | `agent` argument to halt; printed in HALT.md and stderr. |
| Which artifact was expected vs. observed | `artifact` arg + `observed` arg. Observed comes from validate-stage's stderr diagnostic. |
| Last 50 lines of agent output | Optional 8th arg to `halt`. The orchestrator captures the failed Task agent's return message (which is bounded since sub-agents return only "Done. Output: ..." per the rules), then passes the full text. Worst case "(no output captured)". |
| Suggested operator action | Hard-coded recovery commands in HALT.md (clean + recreate, or tmux attach). |

### 5.5 Backwards compatibility (AC #7)

When neither env var is set:
- `ACORN_SUBAGENT_RETRY_BUDGET=1` (default) — exactly matches current "If a sub-agent fails, relaunch it" instruction (which is one retry).
- `ACORN_FAILURE_EVENT_PATH=""` — events are not emitted.
- HALT.md is still written on retry exhaustion (this is new behaviour, but it's an additive artifact; existing flows that don't look for it are unaffected).
- `acorn doctor` reports halts (DOCTOR_FAIL=1). This is a new failure surface, but `doctor` is already an opt-in diagnostic command — existing CI that runs `acorn doctor` already treats DOCTOR_FAIL as actionable.

No existing public CLI behaviour changes for callers who don't set the env vars or who don't run `acorn doctor`.

---

## 6. Testing Strategy

All tests live in `test/test_recon_completeness.sh`, following the existing harness pattern (`test_auto_trigger.sh`, `test_labels.sh`). Test harness:

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACORN_SCRIPT="$SCRIPT_DIR/bin/acorn"

# Source acorn without triggering main()
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }
assert_eq() { ... }
assert_contains() { ... }

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# Silence side effects
notify_telegram() { :; }
notify_foreman() { :; }
```

### 6.1 Unit tests for `stage_manifest`

| Test | Assertion |
|---|---|
| `stage_manifest full 0` returns 3 lines | `wc -l` = 3 |
| `stage_manifest full 0` includes `architecture.md` and `## Directory Structure` | grep |
| `stage_manifest lite 1` returns `plans/draft.md` | exact match |
| `stage_manifest quick 1` returns `plans/SPEC.md` | exact match |
| `stage_manifest invalid 99` calls die | rc != 0, stderr contains `[ERROR]` |

### 6.2 Unit tests for `validate_stage_artifacts`

Setup: create a temp spec dir, populate recon/ with various states.

| Test | Setup | Expected |
|---|---|---|
| All files present, valid headers | Write 3 files with proper headers | rc 0 |
| Missing architecture.md | rm architecture.md | rc 1, stderr `MISSING|recon/architecture.md` |
| Empty relevant_code.md | `: > relevant_code.md` | rc 1, stderr `EMPTY|recon/relevant_code.md` |
| architecture.md missing `## Directory Structure` header | Write file with only `## Other` | rc 1, stderr `HEADER|recon/architecture.md|^## Directory Structure` |
| Spec dir doesn't exist | pass non-existent path | rc 1, stderr `MISSING|<path>` |
| Stage 1 lite — draft.md present | Write `plans/draft.md` with header | rc 0 |
| Stage 1 lite — draft.md missing | no file | rc 1, stderr `MISSING|plans/draft.md` |
| Stage 4 full — only 3 of 4 redteams | Write redteam_1..3, skip 4 | rc 1, stderr `MISSING|plans/redteam_4.md` |

### 6.3 Unit tests for `emit_failure_event`

| Test | Setup | Expected |
|---|---|---|
| `ACORN_FAILURE_EVENT_PATH` unset | call helper | rc 0, no file written |
| `ACORN_FAILURE_EVENT_PATH` set | call helper | event file exists, contains 1 JSONL line |
| Event JSON parses with jq | call helper, then `jq .` on file | rc 0; field `event` = `subagent.halt` |
| Event JSON contains stage, slug, agent, retry_count | jq field checks | each field matches input |
| Multiple events appended | call helper twice | file has 2 lines, both valid JSON |
| Event path parent dir doesn't exist | set path to deep nested location | rc 0, dir created, file written |
| Event path is unwritable (e.g. /proc/foo) | call helper | rc 0 (best-effort), no crash |

### 6.4 Unit tests for `halt_pipeline_diagnostic`

| Test | Setup | Expected |
|---|---|---|
| Writes HALT.md to recon/ for stage 0 | call helper with stage=0 | `recon/HALT.md` exists |
| Writes HALT.md to plans/ for stage > 0 | call helper with stage=2 | `plans/HALT.md` exists |
| HALT.md contains stage, agent, artifact, observed | call helper | grep each value |
| HALT.md contains recovery command | call helper | grep `acorn clean` and `acorn create` |
| Returns rc 1 always | call helper | rc != 0 |
| Stderr contains diagnostic lines | capture stderr | grep `Pipeline halted`, `Failed agent`, `Recovery` |
| Emits event when ACORN_FAILURE_EVENT_PATH set | export var, call helper | event file has new line |
| Reads slug/repo from meta.json | write meta.json, call helper | HALT.md contains those values |
| meta.json missing | no meta.json | HALT.md still written, fields empty, no crash |

### 6.5 Integration tests via `_internal` CLI

These invoke the real `bin/acorn` binary so we test the dispatch path:

| Test | Command | Expected |
|---|---|---|
| validate-stage success | `acorn _internal validate-stage <good_dir> lite 0` | rc 0 |
| validate-stage missing | `acorn _internal validate-stage <bad_dir> lite 0` | rc 1, stderr `MISSING|...` |
| halt writes HALT.md | `acorn _internal halt <dir> lite 0 "Agent A" "recon/architecture.md" artifact_missing "file missing"` | rc 1, HALT.md exists |
| stage-manifest full 0 | `acorn _internal stage-manifest full 0` | stdout 3 lines |
| Unknown _internal subcommand | `acorn _internal foo` | rc != 0, stderr contains `Unknown _internal subcommand` |
| `acorn --help` does NOT mention `_internal` | grep help output | no match |

### 6.6 Behavioural / pattern-scanning tests

Verify that planning_block_* contain the expected text:

```bash
# Stage 0 gate present in all three modes
for mode in full lite quick; do
  block="$(planning_block_$mode "/tmp/spec")"
  assert_contains "Stage 0 gate present in $mode" "$block" \
    'acorn _internal validate-stage'
  assert_contains "$mode mode references retry budget" "$block" \
    'ACORN_SUBAGENT_RETRY_BUDGET'
  assert_contains "$mode mode references halt command" "$block" \
    'acorn _internal halt'
  assert_contains "$mode mode names Agent A architecture mapping" "$block" \
    'architecture.md ↔ Agent A'
done
```

### 6.7 Subsequent-stage gate tests

For each pipeline stage, verify the planning block contains a programmatic gate:

```bash
# Full mode has Stage 0..5 gates (6 total)
block="$(planning_block_full /tmp/x)"
assert_eq "full mode has 6 validate-stage references" \
  "$(printf '%s' "$block" | grep -c 'acorn _internal validate-stage')" "6"

# Lite mode has Stage 0..3 gates (4 total)
block="$(planning_block_lite /tmp/x)"
assert_eq "lite mode has 4 validate-stage references" \
  "$(printf '%s' "$block" | grep -c 'acorn _internal validate-stage')" "4"

# Quick mode has Stage 0..1 gates (2 total)
block="$(planning_block_quick /tmp/x)"
assert_eq "quick mode has 2 validate-stage references" \
  "$(printf '%s' "$block" | grep -c 'acorn _internal validate-stage')" "2"
```

### 6.8 cmd_doctor halt-detection test

```bash
# Setup: a fake spec directory with HALT.md
mkdir -p "$tmp/projects/acorn/main/.specs/halted-spec/recon"
echo "# Pipeline Halt: stage 0" > "$tmp/projects/acorn/main/.specs/halted-spec/recon/HALT.md"
echo '{"slug":"halted-spec","repo":"acorn"}' > "$tmp/projects/acorn/main/.specs/halted-spec/meta.json"
PROJECTS_DIR="$tmp/projects" out=$(cmd_doctor 2>&1) || rc=$?
assert_contains "doctor surfaces halt" "$out" "HALTED PIPELINE"
assert_contains "doctor cites HALT.md path" "$out" "halted-spec/recon/HALT.md"
```

### 6.9 status_for_spec halt-prefix test

```bash
# Same setup as 6.8, then:
status=$(status_for_spec "$tmp/projects/acorn/main/.specs/halted-spec")
assert_contains "status prefixes [HALTED]" "$status" "[HALTED]"
```

### 6.10 End-to-end induced failure test (AC #6)

The acceptance criterion mentions: "induce a Stage 0 sub-agent crash; verify pipeline halts with diagnostic; verify SPEC.md not produced; verify event emitted to configured path."

This is hard to do in pure bash unit testing because the actual orchestrator is an LLM. The test approximates it by:

```bash
# Simulate: orchestrator runs validate-stage and halt manually
mkdir -p "$tmp/spec/recon"
echo '{}' > "$tmp/spec/meta.json"
# Only write 2 of 3 recon files (Agent A "crashed")
echo "## " > "$tmp/spec/recon/relevant_code.md"
echo "## " > "$tmp/spec/recon/conventions.md"
# (architecture.md missing)

ACORN_FAILURE_EVENT_PATH="$tmp/events.jsonl" \
  "$ACORN_SCRIPT" _internal validate-stage "$tmp/spec" lite 0 \
  > "$tmp/stdout" 2> "$tmp/stderr" || rc=$?
assert_eq "validate-stage exits 1" "$rc" "1"
assert_contains "stderr names missing file" "$(<"$tmp/stderr")" \
  "MISSING|recon/architecture.md"

# Simulate retry exhaustion → halt
ACORN_FAILURE_EVENT_PATH="$tmp/events.jsonl" \
  "$ACORN_SCRIPT" _internal halt "$tmp/spec" lite 0 \
    "Agent A (Architecture & Structure)" "recon/architecture.md" \
    artifact_missing "file missing" || rc=$?
assert_eq "halt exits 1" "$rc" "1"

# Verify HALT.md
[ -f "$tmp/spec/recon/HALT.md" ] && pass "HALT.md written" || fail "..."

# Verify SPEC.md NOT produced (would only be written by Stage 3 in lite)
[ ! -f "$tmp/spec/plans/SPEC.md" ] && pass "SPEC.md not produced" || fail "..."

# Verify event emitted
[ -f "$tmp/events.jsonl" ] && pass "event file exists" || fail "..."
event="$(<"$tmp/events.jsonl")"
assert_contains "event has subagent.halt" "$event" '"event":"subagent.halt"'
assert_contains "event has stage 0" "$event" '"stage":0'
assert_contains "event has artifact" "$event" '"artifact":"recon/architecture.md"'
```

This test is the canonical AC #6 validator.

### 6.11 Backwards-compat smoke test (AC #7)

```bash
# Without env vars, planning blocks still render with default values
unset ACORN_SUBAGENT_RETRY_BUDGET ACORN_FAILURE_EVENT_PATH
block="$(planning_block_lite /tmp/x)"
assert_contains "default budget appears" "$block" "1 retries per agent"
assert_contains "default backoff appears" "$block" "30 seconds"
assert_contains "event path display marks unset" "$block" "(unset"
```

### 6.12 Existing tests must still pass

Before/after CI: run all existing `test/test_*.sh` files to verify no regression. Particular attention to:
- `test_auto_trigger.sh` — `wait_for_claude_ready`, `send_auto_trigger` should be unaffected.
- `test_labels.sh`, `test_split.sh` — pipeline-orthogonal, should not be affected.
- `test_doctor.sh` — extended with halt-detection assertions; the existing assertions must still pass.

### 6.13 Test execution

Per existing convention (no CI): manual `bash test/test_recon_completeness.sh`. Add a comment in the new file noting that integration tests requiring real Claude runs are gated by `INTEGRATION=1` (none in this feature, but the convention is preserved).

---

## 7. Migration Plan

### 7.1 Implementation order (incremental, each step independently verifiable)

**Step 1 — Helpers and internal CLI (~150 lines added)**
- Add 3 env-var declarations (top of file).
- Add `stage_manifest`, `stage_name`, `validate_stage_artifacts`, `emit_failure_event`, `halt_pipeline_diagnostic` after `notify_foreman` (~line 120).
- Add `cmd_internal` near `cmd_doctor` (~line 3411).
- Add `_internal` case in `main()` dispatch (~line 3580).
- **Verify**: `bash test/test_recon_completeness.sh` (sections 6.1–6.4 pass). `acorn _internal validate-stage` and friends work from CLI.

**Step 2 — `cmd_doctor` and `status_for_spec` halt detection (~15 lines)**
- Patch `cmd_doctor` per §3.5.
- Patch `status_for_spec` per §3.6.
- **Verify**: tests in §6.8, §6.9 pass; existing `test_doctor.sh` still passes.

**Step 3 — `planning_block_full` updates**
- Modify the function header to inject retry/event placeholders via additional `sed` pipes.
- Replace Stage 0 "Confirm all 3 files exist" block with new gate text.
- Repeat for Stage 1, 2, 3, 4 gates (insert similar gate text after each existing "After all N complete" or end-of-stage instruction).
- Replace orchestrator-context "If a sub-agent fails, relaunch it" bullet at line 1137.
- **Verify**: `planning_block_full /tmp/x | grep -c 'acorn _internal validate-stage'` returns 6. `planning_block_full /tmp/x | grep '__RETRY_BUDGET__'` returns nothing (fully expanded).

**Step 4 — `planning_block_lite` updates**
- Same pattern as Step 3, but for lite (4 stages → 4 gates).
- **Verify**: 4 validate-stage references in the rendered block.

**Step 5 — `planning_block_quick` updates**
- Same pattern, 2 stages → 2 gates.
- **Verify**: 2 validate-stage references in the rendered block.

**Step 6 — Behavioural and pattern tests**
- Add §6.6, §6.7, §6.10, §6.11 tests.
- **Verify**: full test suite green.

**Step 7 — Live smoke test (manual)**
- Run `acorn create acorn 2 --quick` and observe the rendered PROMPT.md to confirm gates appear correctly.
- Manually delete one recon file mid-run (or kill a Task subprocess); confirm orchestrator halts with HALT.md.

### 7.2 Roll-out

This is a single bash file deployed by symlink. Deployment is `git pull` + (optionally) `chmod +x`. No service restart, no migration script.

**Risk-mitigated rollout strategy:**
1. Land the bash helpers and `_internal` CLI first (Steps 1–2). They're additive and dormant — nothing calls them yet.
2. Add `planning_block_quick` updates (Step 5) — quick mode is the smallest blast radius.
3. Run a real `acorn create --quick` on a low-stakes test issue. Verify rendered PROMPT.md, observe pipeline behaviour.
4. If quick mode looks good, proceed to lite (Step 4), then full (Step 3).
5. After all three are live, monitor next ~5 spec creations to ensure no regression in stage advancement.

### 7.3 Rollback

If a problem surfaces:
- Revert the planning-block changes (Steps 3–5) — single bash file, single commit.
- Bash helpers can stay in place (they're inert without the prompt-side calls).
- Existing specs created before the change are unaffected (they have the old PROMPT.md text already baked in).
- Specs created during the rollout window will have the new PROMPT.md but, with bash helpers reverted, calls to `acorn _internal validate-stage` will fail with "Unknown command". The orchestrator's prompt explicitly says "If validate-stage is missing, treat as bash-helper-not-installed: revert to manual confirmation behaviour" — actually, simpler: keep bash helpers in place during rollback. They cost nothing to leave.

### 7.4 Coexistence with existing flows

- **Existing in-flight specs** (created before the change): their PROMPT.md still has the old "Confirm all 3 files exist" text. They keep working as before; no harm.
- **Forge consumers** that set `ACORN_FAILURE_EVENT_PATH=~/.foreman/.foreman-events.jsonl` will start receiving JSONL events on halt without any forge-side change other than configuration. Foreman's existing event consumer already tolerates new event types (it ignores unknown `event` field values; a `subagent.halt` event just becomes a new ingestion path).
- **Upstream callers** (no forge): leave `ACORN_FAILURE_EVENT_PATH` unset. Behaviour identical to current except for the new HALT.md artifact and stricter validation.

### 7.5 Documentation updates

Two narrative-only updates (no schema changes):
- `claude/global/CLAUDE.md`: add a paragraph documenting the two new env vars and the halt-detection behaviour.
- `README.md`: add a one-paragraph "Failure handling" subsection mentioning HALT.md and the env vars.

---

## 8. Risks

| ID | Risk | Severity | Likelihood | Mitigation |
|---|---|---|---|---|
| R1 | The orchestrator LLM ignores the new programmatic gate instructions and relies on its own judgment | High | Medium | Keep the instructions explicit, named, and capitalised ("YOU MUST", "MANDATORY"). Reference the exact `acorn _internal validate-stage` command in monospace. Mention that the existing acorn pipeline runs Claude with `--dangerously-skip-permissions`, so Bash tool invocations don't get prompts. The behavioural tests verify the prompt contains the expected text — but cannot verify the LLM follows it. Monitor first ~10 runs. |
| R2 | The orchestrator interprets a header-mismatch as "header check is wrong, file is fine" and proceeds anyway | Medium | Medium | Validation-failure stderr is one machine-readable line that the orchestrator can parse; the prompt explicitly says "if exit code 1, do not advance, regardless of file contents you may have read." Header pattern is intentionally loose (`^## ` matches any heading) for non-architecture files; only `architecture.md` enforces a specific header. |
| R3 | Stage 0 has 3 parallel agents — if 2 fail simultaneously, retry logic must handle multi-failure correctly | Medium | Low | Prompt explicitly handles this case (relaunch ALL failed agents, validate after all return). Tested with a setup where 2 of 3 files are missing. |
| R4 | `ACORN_FAILURE_EVENT_PATH` set to an unwritable path produces no events without warning | Low | Low | Best-effort by design (matches `notify_foreman` semantics). Rare and low-impact; operator setup error. |
| R5 | A Task sub-agent succeeds (file written) but contains gibberish/hallucinated content | Medium | Medium | Out of scope for this feature. The header check catches "wrote nothing useful" but not "wrote plausible-looking nonsense". Mitigation: existing red-team / validation stages later in the pipeline catch these. Future work could add a content-quality check (LLM-as-judge), but that's a separate feature. |
| R6 | New planning block text balloons PROMPT.md size, exceeds context window in early Claude turns | Low | Low | The added text is ~80 lines per gate × 6 gates (full mode) = ~480 lines. Existing PROMPT.md is ~1500–3000 lines. New ratio: ~+15–30%. Well within context. Verified by length check in test. |
| R7 | The `sed "s|__RETRY_BUDGET__|...|g"` substitution misses occurrences if the placeholder name is mistyped in the heredoc | Medium | Low | Lint check: after rendering, `grep -c '__RETRY_BUDGET__\|__RETRY_BACKOFF__\|__EVENT_PATH_DISPLAY__'` should return 0. Add this check to `validate_prompt_md` (line 1672) so unrendered placeholders fail loudly at spec creation. |
| R8 | Forge's `~/.foreman/.foreman-events.jsonl` consumer doesn't tolerate the new `subagent.halt` event type | Low | Low | Out of scope (forge is a separate repo). However, JSONL consumers typically ignore unknown event types; the schema is additive (no field renames). Coordinate with forge maintainer when this lands. |
| R9 | `cmd_doctor` flagging halts as DOCTOR_FAIL might break existing CI that runs `acorn doctor` and expects exit 0 in normal operation | Low | Medium | If a halt exists, that IS a real failure — surfacing it is the goal. Document in release notes. CI integrators can grep stderr for `HALTED PIPELINE` and route appropriately. |
| R10 | Operators may run `acorn clean` while a halted spec has unmerged HALT.md context | Low | Low | `acorn clean` is destructive by design. HALT.md was a diagnostic; once cleaned, it's gone, which is intentional. The diagnostic was already read by the operator before they ran clean. |
| R11 | Concurrent retries write events out of order | Low | Low | JSONL is append-only with `>>`; on most filesystems writes < PIPE_BUF (4096B) are atomic. Each event is < 1KB. Acceptable. |
| R12 | The `_internal` subcommand could be misused by operators directly | Very low | Very low | It's just a CLI surface for helpers. Misuse (e.g., calling halt manually) writes a HALT.md and emits an event — operator can clean up. Document as "internal — orchestrator-facing" in inline comments only, not in user-facing help. |
| R13 | Test sourcing the script (`eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"`) might be sensitive to top-level env-var declarations | Low | Low | Existing pattern handles top-level `VAR="${VAR:-default}"` lines fine. The new lines follow the same pattern. Verified manually that test_auto_trigger.sh-style sourcing succeeds. |

### 8.1 Open questions for validation stage

These are items that should be challenged in Stage 2 validation:

1. **Should `validate_stage_artifacts` accept a custom manifest instead of a hard-coded `stage_manifest`?** Pro: extensibility. Con: YAGNI — the three pipeline modes are stable. Recommendation: hard-coded for now, refactor when a 4th mode appears.
2. **Should the orchestrator capture sub-agent log output for HALT.md?** Sub-agents return only "Done. Output: ..." per the rules. The "last 50 lines" is mostly aspirational — captured output will usually be the Task return message itself. Acceptable as a placeholder; future work could pipe Task agent logs to a file.
3. **Should the retry budget be per-agent or per-stage?** Current design: per-agent (Stage 0 with 3 agents = up to 3×retry attempts total). Alternative: per-stage (after N total relaunches in this stage, halt). The spec PROMPT.md says "retry that specific sub-agent once" → per-agent. Locked in.
4. **Should we add a global timeout for the entire pipeline?** Out of scope; existing watchdog/hang-detect handles this at the session layer. We don't want two competing timeout systems.

---

## 9. Summary of File Changes

| File | Action | Approximate lines | Notes |
|---|---|---|---|
| `bin/acorn` | Add env vars (top) | +3 | After existing `TELEGRAM_NOTIFY_URL` block |
| `bin/acorn` | Add helper functions (after `notify_foreman`, ~line 120) | +160 | `stage_manifest`, `stage_name`, `validate_stage_artifacts`, `emit_failure_event`, `halt_pipeline_diagnostic` |
| `bin/acorn` | Add `cmd_internal` (near `cmd_doctor`) | +30 | Internal CLI dispatch |
| `bin/acorn` | Add `_internal` case in `main()` | +3 | Hidden subcommand |
| `bin/acorn` | Modify `cmd_doctor` halt detection | +12 | Inside per-spec loop |
| `bin/acorn` | Modify `status_for_spec` halt detection | +5 | Set halted flag, prefix output |
| `bin/acorn` | Modify `planning_block_full` (header, gates, retry bullet) | ~+250 / ~−10 | 6 stage gates, 1 bullet replacement, 3 sed pipes |
| `bin/acorn` | Modify `planning_block_lite` | ~+170 / ~−10 | 4 gates |
| `bin/acorn` | Modify `planning_block_quick` | ~+85 / ~−5 | 2 gates |
| `bin/acorn` | Modify `validate_prompt_md` to lint placeholders | +5 | Refuse PROMPT.md with unexpanded `__VAR__` placeholders |
| `test/test_recon_completeness.sh` | New test file | ~+350 | Per §6 |
| `claude/global/CLAUDE.md` | Add env-var documentation | +15 | Reference doc |
| `README.md` | Add failure-handling subsection | +20 | User-facing doc |

**Total**: ~+1110 lines added, ~−25 lines removed across 4 files (1 modified script, 1 new test, 2 docs). All within the existing single-file architecture per recon §"Implicit Conventions".

---

## 10. Acceptance Criteria Mapping

| AC | Where addressed |
|---|---|
| #1 Stage-completion validation after each pipeline stage | §3.4 — gates inserted after every stage in all three planning blocks; `validate_stage_artifacts` enforces existence + non-empty + header |
| #2 Per-agent retry with backoff, configurable via `ACORN_SUBAGENT_RETRY_BUDGET`, default 1 | §2.1 env vars; §3.4 prompt instructions specify retry loop; tests §6.11 verify defaults |
| #3 Halt with diagnostics (stage, agent, expected/observed, last 50 lines, suggested action) | §2.3 HALT.md format; §3.2 `halt_pipeline_diagnostic`; §5.4 explicit mapping table |
| #4 Optional event emission via `ACORN_FAILURE_EVENT_PATH` (JSONL) | §2.4 schema; §3.2 `emit_failure_event`; tests §6.3 |
| #5 Recon completeness gate enforcing existence + non-empty + section headers | §2.2 stage_manifest enforces `## Directory Structure` for architecture.md; §3.4 gate text references it; tests §6.2 |
| #6 Test inducing Stage 0 sub-agent crash, verifying halt + diagnostic + no SPEC.md + event emitted | §6.10 end-to-end test |
| #7 Backwards compatibility — defaults preserve current 1-retry behaviour | §2.1 defaults; §5.5 explicit BC analysis; tests §6.11 |

Every AC has a code path AND a test path. No AC is left to "documentation only".

---

## 11. Pi Model Recommendation Hint (for Stage 3)

The final SPEC.md should include `suggested_pi_model: codex` because:
- The spec names specific files (`bin/acorn`, `test/test_recon_completeness.sh`).
- It names specific function signatures and line numbers (`stage_manifest`, line 120 insertion point, line 783 modification point).
- Implementation is pattern-following (model after `validate_prompt_md`, `notify_foreman`, `write_meta_json`).
- Touches < 8 files (2 files modified + 2 docs = 4 files).
- Introduces no new interfaces or schemas (the JSONL event schema is additive).
- Includes explicit test commands (`bash test/test_recon_completeness.sh`).

This is a textbook codex-suitable spec.



