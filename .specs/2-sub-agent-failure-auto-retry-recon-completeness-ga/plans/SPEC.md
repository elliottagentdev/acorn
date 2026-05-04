# SPEC: Sub-agent failure auto-retry + recon completeness gate before stage advance

## Pi Model Recommendation

suggested_pi_model: codex
suggested_pi_model_rationale: Spec names exact files, line numbers, and function signatures; implementation is pattern-following against existing acorn idioms (validate_prompt_md, notify_foreman, write_meta_json); touches < 8 files; introduces no new interfaces; includes explicit test commands.

---

## 1. Requirements Traceability Matrix

Each acceptance criterion (AC) from PROMPT.md, mapped to the section of this spec that satisfies it. No AC is deferred.

| AC # | Requirement (verbatim) | Spec section | Code path | Test path | Status |
|---|---|---|---|---|---|
| 1 | **Stage-completion validation**: each stage's expected artifacts must exist AND be non-empty | §3.2 (`stage_manifest`, `validate_stage_artifacts`); §3.5 (gate text inserted after every stage in every mode — 11 gates total, all enumerated verbatim in §3.5.2 / §3.5.3) | `bin/acorn` new helpers + planning_block_* edits | §6.2, §6.7 (gate counts) | COVERED |
| 2 | **Per-agent retry**: `ACORN_SUBAGENT_RETRY_BUDGET` (default 1), with backoff (default 30 s); halt on retry exhaustion | §3.1 env vars; §3.5 prompt text specifies retry loop | Env var read at script top + interpolated into PROMPT.md at render time | §6.6 (retry budget appears in rendered prompt), §6.11 (default values) | COVERED — control flow lives in orchestrator prompt; bash provides primitives |
| 3 | **Halt with diagnostics**: stage, sub-agent, expected vs observed, last 50 lines, suggested action | §3.4 HALT.md format; §3.3 `halt_pipeline_diagnostic` | New helper writes HALT.md + stderr | §6.4 | COVERED. "Last 50 lines" partially aspirational — see Validation Resolution Log F-aspiration / R5 |
| 4 | **Optional event emission**: `ACORN_FAILURE_EVENT_PATH` JSONL with ts, slug, stage, agent, artifact, retry_count, halt_reason | §3.4.2 JSONL schema; §3.3 `emit_failure_event` | New helper appends JSONL | §6.3 | COVERED + EXTENDED with mode/repo/issue_number/stage_name/retry_budget/observed/session_name |
| 5 | **Recon completeness gate**: existence + non-empty + headers (e.g. "## Directory Structure" in architecture.md) | §3.2 `stage_manifest` for stage 0; §3.5.2 (Stage 0 gate text) | Hard-coded in `stage_manifest "<mode>" 0` | §6.2 (header check tests) | COVERED |
| 6 | **Test**: induce Stage 0 sub-agent crash, verify halt + diagnostic + no SPEC.md + event emitted | §6.10 end-to-end synthetic test (documented limitation: simulates by omitting a recon file rather than literally killing a Task subprocess; AC #6 is satisfied at the bash-helper layer; LLM-layer behavior covered by §6.6 prompt-content assertions and a manual smoke step in §7.1 Step 7) | `_internal` CLI dispatch | §6.10 + §7.1 Step 7 manual smoke | COVERED with documented synthetic-test limitation |
| 7 | **Backwards compatibility**: callers not setting retry env var get current behaviour with 1 silent retry | §3.1 defaults; §5 backwards-compat note | Defaults match current "If a sub-agent fails, relaunch it" instruction (1 retry) | §6.11 | COVERED. New surfaces (HALT.md artifact, DOCTOR_FAIL on halts) flagged as additive in release notes (§7.5) |

### 1.1 Constraint coverage (PROMPT.md §Constraints — upstreamable design)

| Constraint | Where addressed |
|---|---|
| Retry budget configurable; sane default (1) preserves current behavior | §3.1 (`ACORN_SUBAGENT_RETRY_BUDGET=1` default) |
| No forge-specific dependencies in the Acorn binary; failure events optionally emit to a configurable target | §3.1 (`ACORN_FAILURE_EVENT_PATH` empty by default; emission is best-effort, no Foreman dependency) |
| Fail-loud philosophy is universally beneficial | §3.3 (`halt_pipeline_diagnostic` writes HALT.md + stderr regardless of forge) |

All constraints satisfied.

---

## 2. Validation Resolution Log

Each finding from `plans/validation.md`, with a one-line summary and resolution (or deferral with severity + follow-up).

### 2.1 Must-fix (CRITICAL / HIGH) — all resolved in this spec

| ID | Finding | Severity | Resolution |
|---|---|---|---|
| F1 | Plan used `redteam_N.md`; codebase actually uses `red_team_N.md` (with underscore) at lines 983–1079 | CRITICAL | **FIXED**. §3.2 `stage_manifest` now uses `red_team_1.md` … `red_team_4.md` for `full:4`. §3.5.3 references the same. |
| F2 | `status_for_spec` has two return paths; plan was ambiguous about which gets `[HALTED]` prefix | HIGH | **FIXED**. §3.7 explicitly applies the `[HALTED] ` prefix to BOTH return paths (label-found and fallback). Test §6.9 covers both paths. |
| F3 | `DOCTOR_FAIL` is read at line 3539 but never initialized → latent `set -u` bug | HIGH | **FIXED**. §3.6 instructs implementer to initialize `DOCTOR_FAIL=0` at the top of `cmd_doctor` (a drive-by fix, justified because the new halt-detection patch reads the same variable). |
| §3.1 | Plan only showed Stage 0 gate text verbatim; remaining 10 stages described as "[same retry / halt protocol as Stage 0]" — implementer ambiguity | HIGH | **FIXED**. §3.5.2 (Stage 0 — 3 modes), §3.5.3 (subsequent multi-agent stages: full Stage 1 drafts, full Stage 4 redteam), and §3.5.4 (subsequent single-agent stages: full 2/3/5, lite 1/2/3, quick 1) provide all 11 gate texts verbatim with their agent-name → relpath mappings. |
| §3.4 | `<MODE>` placeholder relied on orchestrator filling it in — should be hard-coded at render time | HIGH | **FIXED**. §3.5.1 adds a fourth `__MODE__` sed substitution so the rendered PROMPT.md contains literal `full`/`lite`/`quick` — the orchestrator never sees `<MODE>`. |
| §3.11 | `cmd_doctor` halt detection placed inside the running-session loop misses halts in dead sessions | HIGH | **FIXED**. §3.6 places the halt scan in a SEPARATE, INDEPENDENT loop that runs over every spec dir under `$PROJECTS_DIR/*/main/.specs/*/`, regardless of session state. |
| §7.1 | Plan step ordering: `validate_prompt_md` placeholder lint added before placeholders existed in heredocs would break Steps 1–4 | HIGH | **FIXED**. §8.1 reorders implementation: lint check is added in Step 6 (after Steps 3–5 install all `__RETRY_*` placeholders). Phased rollout safe. |
| §3.8 | `validate_stage_artifacts` exited on first failure → orchestrator must re-run after each relaunch (slow for parallel stages) | HIGH | **FIXED**. §3.2 updated: `validate_stage_artifacts` accumulates ALL failures (one stderr line per failure), returning rc=1 if any failed. Orchestrator can relaunch all failed agents in a single Task batch. |

### 2.2 Should-fix (MEDIUM) — all resolved or accepted with documentation

| ID | Finding | Severity | Resolution |
|---|---|---|---|
| F6 | `--no-auto` mode runs Claude WITHOUT `--dangerously-skip-permissions`; new Bash tool calls would prompt | MEDIUM | **DOCUMENTED**. §5.4 adds an operational note: when running `acorn create --no-auto`, the operator must approve each `acorn _internal validate-stage` Bash invocation. No code change needed. |
| F9 / §3.10 | "Verbatim" relaunch prompt is ambiguous — orchestrator may copy imperfectly | MEDIUM | **CLARIFIED**. §3.5.2 prompt text now says: "Use the EXACT prompt block defined for Agent A/B/C earlier in this Stage 0 section, copied character-for-character." |
| §3.7 | Non-numeric / negative `ACORN_SUBAGENT_RETRY_BUDGET` could leak into rendered PROMPT.md | MEDIUM | **FIXED**. §3.5.1 sanitizes `retry_budget` and `retry_backoff` to digits-only via a `case` block before sed substitution; non-digits → defaults. |
| E1 | HALT.md write fails on read-only FS; operator loses diagnostic | MEDIUM | **FIXED**. §3.3 `halt_pipeline_diagnostic` falls back to printing the FULL HALT.md content to stderr via `warn` if the file write fails (`tee >&2` pattern). |
| E10 / C2 | 30 s retry sleep may trigger Foreman watchdog "stalled session" detection | MEDIUM | **DOCUMENTED + MITIGATED**. §3.5.2 prompt text writes a sentinel file `__SPEC_PATH__/.retry-pending` before the sleep (touches mtime so watchdog sees activity), and removes it after. §5.5 documents the interaction. |
| S2 | `cmd_internal halt`'s `spec_dir` arg unvalidated → orchestrator hallucination could write HALT.md anywhere | MEDIUM | **FIXED**. §3.3 `cmd_internal halt` validates that `spec_dir` is under `$PROJECTS_DIR/*/main/.specs/*/` using a path-prefix check (matches `cmd_clean`'s safety pattern at lines ~2530). Refuses with `die` otherwise. |
| C6 | Orchestrator may misinterpret `acorn _internal halt` rc=1 as "halt command failed" | MEDIUM | **CLARIFIED**. §3.5.2 prompt text says: "Note: `acorn _internal halt` ALWAYS exits non-zero by design — this is the success signal that the halt was recorded. After running halt, your final response is `Pipeline halted at Stage N. See <halt_path>.`" |
| §3.12 / E11 | Header-presence check is heuristic — partial-write success possible (file with one header but no body) | MEDIUM | **ACCEPTED + DOCUMENTED**. §10 Risk Register R5: AC #1 only mandates "non-empty"; deeper content quality is out of scope. Future work item: LLM-as-judge content quality check. |
| §3.5 / ER7 | Race: `validate-stage` could read a file mid-write | MEDIUM | **FIXED via prompt**. §3.5.2 explicitly says: "MUST wait for ALL Task agents to RETURN before running validate-stage." |

### 2.3 Nice-to-have (LOW) — resolved with minor edits

| ID | Finding | Severity | Resolution |
|---|---|---|---|
| F4 | `_internal` case insertion point in `main()` not pinpointed | LOW | **FIXED**. §3.3 says: "insert the `_internal)` case BEFORE the `*)` catch-all currently at lines 3683–3686." |
| F5 | sed pipe style choice (single vs multi-line) ambiguous | LOW | **FIXED**. §3.5.1 commits to multi-line backslash continuation (matches existing function style; minimises diff vs `-e` flag refactor). |
| §3.9 | `agent_log_tail` may contain triple-backticks, breaking markdown | LOW | **FIXED**. §3.3 `halt_pipeline_diagnostic` sanitises `agent_log_tail` by replacing ` ``` ` → ` ~~~ ` before writing. |
| E20 | If both `recon/HALT.md` and `plans/HALT.md` exist, only one is reported | LOW | **FIXED**. §3.6 reports BOTH paths if both exist (loop over both candidates, warn for each). |
| C5 | Event name `subagent.halt` not pinned in spec | LOW | **PINNED**. §3.4.2 declares `event = "subagent.halt"` as the canonical event type. Tests §6.3 assert this exact string. |
| §3.2 sed sed-injection (S1) | Sed metacharacters (`|`, `\`) in env var values could corrupt substitution | LOW | **DOCUMENTED**. §5.4 notes "ACORN_FAILURE_EVENT_PATH must not contain `|` or `\`. Operator-controlled value; not from untrusted source." |
| §3.5 / ER10 | `validate_prompt_md` placeholder lint rejects PROMPT.md with stale placeholders — fail-loud at render time | LOW | **IMPLEMENTED**. §3.8 patches `validate_prompt_md` to reject any of `__SPEC_PATH__|__RETRY_BUDGET__|__RETRY_BACKOFF__|__EVENT_PATH_DISPLAY__|__MODE__` remaining in the rendered file. |
| E18 | Halted spec approved before HALT.md removed | LOW | **NOT CHANGED**. `cmd_approve` already requires SPEC.md presence; halted Stage 0 → no SPEC.md → approve fails naturally. Future-proofing for post-SPEC.md halts deferred. |

### 2.4 Deferred items (with severity + recommended follow-up)

| ID | Item | Severity | Why deferred | Recommended follow-up |
|---|---|---|---|---|
| R5 / E11 | Header-only validation does not catch hallucinated/partial recon (motivating Wave 1 #125 incident) | MEDIUM | AC #1 mandates only "non-empty"; deeper content validation requires LLM-as-judge or schema-based check (separate feature) | File a follow-up issue: "Add LLM-as-judge content-quality validation to recon stage". Owner: acorn maintainer. |
| AC #6 literal-fidelity | Test simulates a Stage 0 crash by omitting a file rather than literally killing a Task subprocess | LOW | Pure-bash unit tests cannot drive the LLM orchestrator end-to-end. Documented in §6.10 + §7.1 Step 7 manual smoke covers the live path | First 10 production runs after rollout: operator inspects each rendered PROMPT.md and observes one synthetic crash injection (delete a recon file mid-run). Document outcomes in DONE.md. |
| R8 | Forge JSONL consumer compatibility for the new `subagent.halt` event | LOW | Forge is a separate repo; coordination via release notes | Notify forge maintainer when this lands; verify no consumer crashes on `subagent.halt`. Forge already tolerates unknown event types (per validation §2.3 row R8). |
| R6 | PROMPT.md size growth (~+15–30%) | LOW | Within Claude context window; verified by token-budget calculation in validation §4.1 | Monitor first ~5 spec creations; if context pressure surfaces, tighten gate text in a subsequent revision. |

---

## 3. Implementation Plan

All changes are confined to four files: `bin/acorn`, the new `test/test_recon_completeness.sh`, `claude/global/CLAUDE.md`, and `README.md`. The codebase is a single bash file (`/home/agentdev/projects/acorn/main/bin/acorn`, 3690 lines) per recon §"Directory Structure".

### 3.1 New top-level environment variables

Insert immediately after `TELEGRAM_NOTIFY_URL=...` (currently at `bin/acorn:10`):

```bash
ACORN_SUBAGENT_RETRY_BUDGET="${ACORN_SUBAGENT_RETRY_BUDGET:-1}"
ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS="${ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS:-30}"
ACORN_FAILURE_EVENT_PATH="${ACORN_FAILURE_EVENT_PATH:-}"
```

| Variable | Default | Effect when unset / default |
|---|---|---|
| `ACORN_SUBAGENT_RETRY_BUDGET` | `1` | One retry per sub-agent (matches today's narrative "If a sub-agent fails, relaunch it" instruction) |
| `ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS` | `30` | 30 s pause between retries |
| `ACORN_FAILURE_EVENT_PATH` | `""` | Event emission disabled |

These values are interpolated into PROMPT.md at render time (`planning_block_*`), so each spec's pipeline is pinned to the values that were active when `acorn create` ran.

### 3.2 New helper functions: `stage_manifest`, `stage_name`, `validate_stage_artifacts`

Insert immediately AFTER `notify_foreman` ends (currently `bin/acorn:119`) and BEFORE `check_circuit_breaker` (currently `bin/acorn:121`).

```bash
# ---------------------------------------------------------------------------
# stage_manifest <mode> <stage>
# Returns the expected artifacts and required header-regex per artifact for
# a given pipeline mode and stage index. One line per artifact, fields
# delimited by '|':  <relpath>|<grep -E pattern>
# Header pattern '^## ' matches any markdown level-2 header (proves file
# isn't whitespace). Stage 0 architecture.md requires '^## Directory Structure'
# explicitly, per AC #5.
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
        'plans/red_team_1.md|^## ' \
        'plans/red_team_2.md|^## ' \
        'plans/red_team_3.md|^## ' \
        'plans/red_team_4.md|^## '
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

# ---------------------------------------------------------------------------
# stage_name <mode> <stage> -> human-readable stage label
# ---------------------------------------------------------------------------
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
# Iterates the manifest, accumulates ALL failing artifacts (not first-fail-
# only), and emits one stderr line per failure of the form:
#   MISSING|<relpath>
#   EMPTY|<relpath>
#   HEADER|<relpath>|<pattern>
# Returns rc 0 if every artifact passes; rc 1 if any failed.
# ---------------------------------------------------------------------------
validate_stage_artifacts() {
  local spec_dir="$1" mode="$2" stage="$3"
  if [ ! -d "$spec_dir" ]; then
    printf 'MISSING|%s\n' "$spec_dir" >&2
    return 1
  fi
  local manifest path header full rc=0
  manifest="$(stage_manifest "$mode" "$stage")"
  while IFS='|' read -r path header; do
    [ -n "$path" ] || continue
    full="$spec_dir/$path"
    if [ ! -f "$full" ]; then
      printf 'MISSING|%s\n' "$path" >&2
      rc=1
      continue
    fi
    if [ ! -s "$full" ]; then
      printf 'EMPTY|%s\n' "$path" >&2
      rc=1
      continue
    fi
    if [ -n "$header" ] && ! grep -E -q -- "$header" "$full"; then
      printf 'HEADER|%s|%s\n' "$path" "$header" >&2
      rc=1
      continue
    fi
  done <<< "$manifest"
  return "$rc"
}
```

### 3.3 New helper functions: `emit_failure_event`, `halt_pipeline_diagnostic`

Append AFTER `validate_stage_artifacts` (still in the new helper block, before `check_circuit_breaker`).

```bash
# ---------------------------------------------------------------------------
# emit_failure_event — append a JSONL event line when ACORN_FAILURE_EVENT_PATH
# is set. Best-effort: missing jq, unwritable path, etc. all return 0.
# Args (positional, all required, "" allowed for empties):
#   slug stage stage_name agent artifact retry_count retry_budget
#   halt_reason observed mode repo issue_number session_name
# ---------------------------------------------------------------------------
emit_failure_event() {
  local event_path="${ACORN_FAILURE_EVENT_PATH:-}"
  [ -n "$event_path" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local slug="${1:-}" stage="${2:-0}" sname="${3:-}" agent="${4:-}"
  local artifact="${5:-}" retry_count="${6:-0}" retry_budget="${7:-0}"
  local halt_reason="${8:-}" observed="${9:-}" mode="${10:-}"
  local repo="${11:-}" issue_number="${12:-0}" session_name="${13:-}"

  # Sanitize numerics: fall back to 0 if non-digits.
  case "$stage" in ''|*[!0-9]*) stage=0 ;; esac
  case "$retry_count" in ''|*[!0-9]*) retry_count=0 ;; esac
  case "$retry_budget" in ''|*[!0-9]*) retry_budget=0 ;; esac
  case "$issue_number" in ''|*[!0-9]*) issue_number=0 ;; esac

  local payload
  payload="$(jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg slug "$slug" \
    --argjson stage "$stage" \
    --arg stage_name "$sname" \
    --arg agent "$agent" \
    --arg artifact "$artifact" \
    --argjson retry_count "$retry_count" \
    --argjson retry_budget "$retry_budget" \
    --arg halt_reason "$halt_reason" \
    --arg observed "$observed" \
    --arg mode "$mode" \
    --arg repo "$repo" \
    --argjson issue_number "$issue_number" \
    --arg session_name "$session_name" \
    '{ts:$ts, source:"acorn", event:"subagent.halt",
      slug:$slug, repo:$repo, issue_number:$issue_number, mode:$mode,
      stage:$stage, stage_name:$stage_name, agent:$agent,
      artifact:$artifact, retry_count:$retry_count, retry_budget:$retry_budget,
      halt_reason:$halt_reason, observed:$observed,
      session_name:$session_name}' 2>/dev/null)" || return 0

  mkdir -p "$(dirname "$event_path")" 2>/dev/null || true
  printf '%s\n' "$payload" >> "$event_path" 2>/dev/null || true
  return 0
}

# ---------------------------------------------------------------------------
# halt_pipeline_diagnostic <spec_dir> <mode> <stage> <agent> <artifact>
#                           <halt_reason> <observed> [<agent_log_tail>]
# Writes HALT.md (recon/HALT.md for stage 0, plans/HALT.md otherwise),
# prints stderr diagnostic via warn(), emits JSONL event. Always rc 1.
# If HALT.md write fails (read-only FS), the entire HALT body is dumped to
# stderr so the operator can capture it from logs.
# ---------------------------------------------------------------------------
halt_pipeline_diagnostic() {
  local spec_dir="$1" mode="$2" stage="$3" agent="$4"
  local artifact="$5" halt_reason="$6" observed="$7"
  local agent_log_tail="${8:-(no output captured)}"

  # Sanitize triple-backticks in agent_log_tail to avoid breaking the
  # markdown fence in HALT.md.
  agent_log_tail="${agent_log_tail//\`\`\`/~~~}"

  local stage_dir
  case "$stage" in
    0) stage_dir="$spec_dir/recon" ;;
    *) stage_dir="$spec_dir/plans" ;;
  esac
  mkdir -p "$stage_dir" 2>/dev/null || true
  local halt_path="$stage_dir/HALT.md"

  local sname
  sname="$(stage_name "$mode" "$stage")"

  # Read meta.json values fail-soft.
  local slug repo issue_number session_name
  slug="$(jq -r '.slug // ""' "$spec_dir/meta.json" 2>/dev/null || true)"
  repo="$(jq -r '.repo // ""' "$spec_dir/meta.json" 2>/dev/null || true)"
  issue_number="$(jq -r '.issue_number // 0' "$spec_dir/meta.json" 2>/dev/null || printf '0')"
  session_name="$(jq -r '.session_name // ""' "$spec_dir/meta.json" 2>/dev/null || true)"

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Build the HALT body once, write to file (best-effort), then dump to
  # stderr if write failed.
  local body
  body="$(
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
  )"

  if ! printf '%s' "$body" > "$halt_path" 2>/dev/null; then
    warn "Failed to write $halt_path; dumping HALT diagnostic to stderr:"
    printf '%s\n' "$body" >&2
  fi

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

### 3.4 New `_internal` CLI subcommand and dispatch

#### 3.4.1 New function `cmd_internal`

Insert immediately BEFORE `cmd_doctor` (currently `bin/acorn:3411`):

```bash
# ---------------------------------------------------------------------------
# cmd_internal — undocumented subcommand surface used by the orchestrator
# (and tests). Not in --help. Each sub validates its own arity.
# ---------------------------------------------------------------------------
cmd_internal() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    validate-stage)
      [ "$#" -eq 3 ] || die "Usage: acorn _internal validate-stage <spec_dir> <mode> <stage>"
      validate_stage_artifacts "$1" "$2" "$3"
      ;;
    halt)
      [ "$#" -ge 7 ] || die "Usage: acorn _internal halt <spec_dir> <mode> <stage> <agent> <artifact> <halt_reason> <observed> [<agent_log_tail>]"
      # Path-prefix safety check — refuse to write HALT.md outside a spec dir.
      local sd="$1"
      case "$sd" in
        "${PROJECTS_DIR%/}"/*/main/.specs/*) ;;
        *) die "Refusing halt: spec_dir must be under \$PROJECTS_DIR/<repo>/main/.specs/<slug> (got: $sd)" ;;
      esac
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

#### 3.4.2 Dispatch wiring in `main()`

Insert the `_internal)` case in `main()` (currently `bin/acorn:3559–3688`) BEFORE the `*)` catch-all at lines 3683–3686:

```bash
  _internal)
    shift
    cmd_internal "$@"
    ;;
```

`_internal` is intentionally absent from any help / usage output.

### 3.5 `planning_block_*` modifications

The three planning-block functions (`planning_block_full`, `planning_block_lite`, `planning_block_quick`) generate the orchestrator-facing PROMPT.md content. The feature replaces the existing narrative "Confirm all N files exist" / "If a sub-agent fails, relaunch it" instructions with explicit, programmatic gate text.

#### 3.5.1 Header changes for all three functions (sed pipeline + sanitisation)

Modify the function header at:
- `planning_block_full` — `bin/acorn:673–675`
- `planning_block_lite` — `bin/acorn:1141–1143`
- `planning_block_quick` — `bin/acorn:1419–1421`

Replace the existing `cat <<'METHODOLOGY_EOF' | sed "s|__SPEC_PATH__|${spec_path}|g"` line with a sanitisation block + multi-pipe:

```bash
planning_block_full() {
  local spec_path="${1:-.}"
  local retry_budget="${ACORN_SUBAGENT_RETRY_BUDGET:-1}"
  local retry_backoff="${ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS:-30}"
  local event_path="${ACORN_FAILURE_EVENT_PATH:-}"
  local event_path_display="${event_path:-(unset — events disabled)}"
  local mode="full"  # for planning_block_lite: "lite"; planning_block_quick: "quick"

  # Sanitize numerics: digits-only or fall back to defaults.
  case "$retry_budget" in ''|*[!0-9]*) retry_budget=1 ;; esac
  case "$retry_backoff" in ''|*[!0-9]*) retry_backoff=30 ;; esac

  cat <<'METHODOLOGY_EOF' \
    | sed "s|__SPEC_PATH__|${spec_path}|g" \
    | sed "s|__RETRY_BUDGET__|${retry_budget}|g" \
    | sed "s|__RETRY_BACKOFF__|${retry_backoff}|g" \
    | sed "s|__EVENT_PATH_DISPLAY__|${event_path_display}|g" \
    | sed "s|__MODE__|${mode}|g"
```

The same edit (with `mode="lite"` or `mode="quick"`) applies to the lite and quick variants.

#### 3.5.2 Stage 0 gate text (replaces existing "Confirm all 3 files exist" line at full:783, lite:1253, quick:1529)

Replace the single-line `**After all 3 complete:** Confirm all 3 files exist (...)` with the following block, IDENTICAL across all three modes (the `__MODE__` placeholder is substituted at render time):

```
**After all 3 complete (Recon Completeness Gate — MANDATORY before Stage 1):**

You MUST wait for ALL 3 Task agents to RETURN before running validation. Then run, via the Bash tool:

    acorn _internal validate-stage "__SPEC_PATH__" __MODE__ 0

The validator checks that ALL THREE artifacts:
  - __SPEC_PATH__/recon/architecture.md   (must contain "## Directory Structure")
  - __SPEC_PATH__/recon/relevant_code.md  (must contain at least one "## " header)
  - __SPEC_PATH__/recon/conventions.md    (must contain at least one "## " header)
exist AND are non-empty.

**Exit code 0**: validation passed. Proceed to Stage 1. Do NOT read the files.

**Exit code 1**: validation failed. Stderr contains ONE LINE PER FAILED ARTIFACT:
  - `MISSING|<relpath>`           — agent's file does not exist
  - `EMPTY|<relpath>`             — agent's file is zero bytes
  - `HEADER|<relpath>|<pattern>`  — agent's file lacks the required header

Map each failed relpath to its agent:
  - `recon/architecture.md`  → Agent A (Architecture & Structure)
  - `recon/relevant_code.md` → Agent B (Relevant Code)
  - `recon/conventions.md`   → Agent C (Conventions & Constraints)

Retry protocol on validation failure:

  1. Touch a sentinel file so the watchdog sees activity during the backoff:
        touch "__SPEC_PATH__/.retry-pending"
  2. Wait __RETRY_BACKOFF__ seconds:
        sleep __RETRY_BACKOFF__
  3. Remove the sentinel:
        rm -f "__SPEC_PATH__/.retry-pending"
  4. Relaunch ONLY the failed agents — in a SINGLE message containing one Task
     tool call per failed agent (parallel). Do NOT re-run agents whose files
     passed. Use the EXACT prompt block defined for Agent A/B/C earlier in
     this Stage 0 section, copied character-for-character.
  5. After the relaunched Task(s) RETURN, re-run validate-stage.
  6. Retry budget is __RETRY_BUDGET__ retries per agent (configurable via
     ACORN_SUBAGENT_RETRY_BUDGET env var). After exhaustion, you MUST halt:

        acorn _internal halt "__SPEC_PATH__" __MODE__ 0 \
            "<agent name>" "<failed relpath>" \
            <halt_reason> "<observed>"

     where:
       <halt_reason> is one of: artifact_missing, artifact_empty,
                                header_missing, retry_exhausted
       <observed>    is a short string describing what was seen
                     (e.g. "file missing", "file empty",
                      "no '## Directory Structure' header")

     The halt command writes __SPEC_PATH__/recon/HALT.md, emits a JSONL
     failure event when ACORN_FAILURE_EVENT_PATH is set
     (currently: __EVENT_PATH_DISPLAY__).

     IMPORTANT: `acorn _internal halt` ALWAYS exits non-zero by design.
     This is the success signal — the halt was recorded. Do NOT interpret
     rc=1 as "halt command failed."

  7. After running halt, STOP. Do NOT advance to Stage 1. Do NOT do the
     failed agent's work yourself as a fallback. Your final response must be:
     "Pipeline halted at Stage 0 (recon). See __SPEC_PATH__/recon/HALT.md."

Only when validate-stage exits 0 may you proceed to Stage 1. Do NOT read
the recon files yourself.
```

#### 3.5.3 Subsequent multi-agent stages: full Stage 1 (drafts) and full Stage 4 (red-team)

For `planning_block_full`, after Stage 1's existing "After all 4 drafts complete" instruction (currently the `master_plan.md` section transition), insert the following gate. Same template applies after Stage 4 with substituted values.

**Full Stage 1 → Stage 2 gate** (insert after the four-drafter `Task` instructions, before the existing transition to Stage 2 "Master Plan"):

```
**After all 4 drafts complete (Stage 1 Completion Gate — MANDATORY before Stage 2):**

Run, via the Bash tool:

    acorn _internal validate-stage "__SPEC_PATH__" full 1

Maps:
  - `plans/draft_plan_1.md` → Drafter 1 (Minimal Surgery lens)
  - `plans/draft_plan_2.md` → Drafter 2 (Clean Architecture lens)
  - `plans/draft_plan_3.md` → Drafter 3 (Robustness lens)
  - `plans/draft_plan_4.md` → Drafter 4 (Developer Experience lens)

[Same retry/halt protocol as Stage 0, with these substitutions:
  - replace "Stage 1" → "Stage 2"
  - replace "recon/" → "plans/"
  - replace "Agent A/B/C" → "Drafter 1/2/3/4"
  - halt command: `acorn _internal halt "__SPEC_PATH__" full 1 …`
  - HALT.md path: `__SPEC_PATH__/plans/HALT.md`]
```

**Full Stage 4 → Stage 5 gate** (after the four red-team `Task` instructions):

```
**After all 4 red-team agents complete (Stage 4 Completion Gate — MANDATORY before Stage 5):**

Run, via the Bash tool:

    acorn _internal validate-stage "__SPEC_PATH__" full 4

Maps:
  - `plans/red_team_1.md` → Red-team 1
  - `plans/red_team_2.md` → Red-team 2
  - `plans/red_team_3.md` → Red-team 3
  - `plans/red_team_4.md` → Red-team 4

[Same retry/halt protocol as Stage 0, with mode=full, stage=4, agent labels
"Red-team N", and HALT.md at __SPEC_PATH__/plans/HALT.md]
```

#### 3.5.4 Subsequent single-agent stages

Each single-agent stage (full Stage 2/3/5; lite Stage 1/2/3; quick Stage 1) gets a simpler gate. Template (parameterised by `<MODE>`, `<STAGE>`, `<NEXT>`, `<RELPATH>`, `<AGENT_LABEL>`):

```
**After the agent completes (Stage <STAGE> Completion Gate — MANDATORY before <NEXT>):**

Wait for the Task agent to RETURN. Then run, via the Bash tool:

    acorn _internal validate-stage "__SPEC_PATH__" <MODE> <STAGE>

Expected artifact: __SPEC_PATH__/<RELPATH>

[Same retry/halt protocol as Stage 0, with these substitutions:
  - mode=<MODE>, stage=<STAGE>
  - single agent: <AGENT_LABEL>
  - on retry: relaunch ONLY this agent with its original prompt verbatim
  - on retry exhaustion: `acorn _internal halt "__SPEC_PATH__" <MODE> <STAGE> "<AGENT_LABEL>" "<RELPATH>" <halt_reason> "<observed>"`
  - HALT.md path: __SPEC_PATH__/plans/HALT.md
  - "advance to <NEXT>" / "halt at Stage <STAGE>"]
```

Concrete substitutions (each gate is rendered as plain text in PROMPT.md):

| Mode | Stage | NEXT | RELPATH | AGENT_LABEL |
|---|---|---|---|---|
| full | 2 | Stage 3 | plans/evaluation.md | Evaluator |
| full | 3 | Stage 4 | plans/master_plan.md | Master Planner |
| full | 5 | spec finalisation | plans/SPEC.md | Final Spec Synthesiser |
| lite | 1 | Stage 2 | plans/draft.md | Plan Drafter |
| lite | 2 | Stage 3 | plans/validation.md | Plan Validator |
| lite | 3 | spec finalisation | plans/SPEC.md | Final Spec Agent |
| quick | 1 | spec finalisation | plans/SPEC.md | Final Spec Agent |

**Total gate count** (for verification by §6.7 tests):
- `planning_block_full` → 6 gates (stages 0..5)
- `planning_block_lite` → 4 gates (stages 0..3)
- `planning_block_quick` → 2 gates (stages 0..1)

#### 3.5.5 Replace orchestrator context-management bullet

In each planning block, replace the existing bullet:

> `- If a sub-agent fails, relaunch it. Do NOT do its work yourself as a fallback.`

at lines:
- `planning_block_full` line 1137
- `planning_block_lite` line 1415
- `planning_block_quick` line 1605

with:

```
- If a sub-agent fails (validate-stage returns non-zero), relaunch ONLY the
  failed agent(s). Wait __RETRY_BACKOFF__ s between retries. Retry budget is
  __RETRY_BUDGET__ retries per agent. On exhaustion, run
  `acorn _internal halt …` (which always exits 1 by design — that is the
  success signal that the halt was recorded) and STOP. Do NOT do the failed
  agent's work yourself as a fallback. The halt diagnostic file
  (HALT.md in the stage's output directory) is authoritative — operators
  triage from it.
```

### 3.6 `cmd_doctor` halt detection (independent loop)

Modify `cmd_doctor` (currently `bin/acorn:3411–3557`).

**Step A — initialise `DOCTOR_FAIL`** (drive-by fix for the latent `set -u` bug at line 3539):

At the top of `cmd_doctor`, immediately after `local …` declarations, add:

```bash
DOCTOR_FAIL=0
```

**Step B — independent halt scan loop**, placed AFTER the existing per-session loop (so it runs even when no sessions are alive). Insert after the existing per-spec/session iteration block, before the final `[ "$DOCTOR_FAIL" -ne 0 ]` exit check at ~line 3539:

```bash
# Halt artifact scan — independent of session state, so halts in dead
# sessions are still surfaced.
local halt_pat halt_file halt_relpath
for halt_pat in "$PROJECTS_DIR"/*/main/.specs/*/recon/HALT.md \
                "$PROJECTS_DIR"/*/main/.specs/*/plans/HALT.md; do
  for halt_file in $halt_pat; do
    [ -f "$halt_file" ] || continue
    halt_relpath="${halt_file#"$PROJECTS_DIR/"}"
    warn "HALTED PIPELINE: $halt_relpath"
    warn "  $(head -n 1 "$halt_file" 2>/dev/null || true)"
    DOCTOR_FAIL=1
  done
done
```

The double `for` (over patterns then over expanded filenames) ensures both `recon/HALT.md` AND `plans/HALT.md` for the same spec are surfaced if both exist.

### 3.7 `status_for_spec` halt prefix

Modify `status_for_spec` (currently `bin/acorn:1999–2037`). The function has TWO return paths: (a) when an issue lifecycle label is found via `gh`, returns the label name; (b) fallback returning one of `review`/`planning`/`unknown`.

Add halt detection near the top of the function, then prefix BOTH return paths.

```bash
status_for_spec() {
  local spec_path="$1"
  local halted=0
  [ -f "$spec_path/recon/HALT.md" ] && halted=1
  [ -f "$spec_path/plans/HALT.md" ] && halted=1
  local prefix=""
  [ "$halted" -eq 1 ] && prefix="[HALTED] "

  # ... existing logic that may early-return with a label name ...
  # Wherever the function does `printf '%s' "$label"; return 0`, change to
  # `printf '%s%s' "$prefix" "$label"; return 0`.
  # Wherever the function does the fallback printf at the end, change to
  # `printf '%s%s' "$prefix" "$fallback_status"`.
}
```

The implementer must locate every `return 0` / final `printf` in this function and apply the prefix. Tests §6.9 cover both paths.

### 3.8 `validate_prompt_md` placeholder lint

Modify `validate_prompt_md` (currently `bin/acorn:1672–1676`). Add a placeholder-leak check AFTER the existing anchor check:

```bash
validate_prompt_md() {
  local prompt_path="$1"
  grep -q 'PLANNING METHODOLOGY — MANDATORY INSTRUCTIONS' "$prompt_path" || return 1
  # Refuse PROMPT.md that still contains unsubstituted template placeholders.
  if grep -E -q '__SPEC_PATH__|__RETRY_BUDGET__|__RETRY_BACKOFF__|__EVENT_PATH_DISPLAY__|__MODE__' "$prompt_path"; then
    return 1
  fi
  return 0
}
```

This causes `cmd_create` to fail loudly at render time if any `planning_block_*` function forgets a sed substitution. **IMPORTANT (per validation §3.13)**: this lint MUST be added LAST, after Steps 3–5 (planning-block edits). See §8.1 step ordering.

### 3.9 `cmd_clean` — no change required

`cmd_clean` (currently `bin/acorn:2471–…`) already does `rm -rf` on the spec directory under a path-safety check. HALT.md is removed automatically. Test §6.12 confirms.

### 3.10 Documentation updates (additive, narrative only)

#### 3.10.1 `claude/global/CLAUDE.md`

Add a new section after the existing pipeline-modes documentation:

```markdown
## Failure Handling

Acorn pipelines validate that each stage's expected artifacts exist (and are
non-empty) before advancing. On failure, the orchestrator retries the failed
sub-agent up to `ACORN_SUBAGENT_RETRY_BUDGET` times (default 1), waiting
`ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS` (default 30) between retries. After
exhaustion, the pipeline halts and writes a `HALT.md` diagnostic to the
relevant stage directory.

| Env var | Default | Effect |
|---|---|---|
| `ACORN_SUBAGENT_RETRY_BUDGET` | `1` | Per-agent retry budget |
| `ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS` | `30` | Pause before each retry |
| `ACORN_FAILURE_EVENT_PATH` | unset | If set, append JSONL `subagent.halt` events to this path |

`acorn doctor` reports halted pipelines with `HALTED PIPELINE: …` and exits
non-zero. `acorn list` / `acorn status` prefix halted specs with `[HALTED]`.
```

#### 3.10.2 `README.md`

Add a brief "Failure Handling" subsection in the existing user-facing doc:

```markdown
### Failure handling

If a sub-agent fails to produce its expected artifact, Acorn retries it once
(configurable via `ACORN_SUBAGENT_RETRY_BUDGET`). On retry exhaustion, the
pipeline halts; a `HALT.md` diagnostic is written to the relevant stage dir
(e.g. `.specs/<slug>/recon/HALT.md`). Run `acorn doctor` to surface halted
pipelines, or `acorn clean <repo> <slug> --yes && acorn create <repo> <issue>`
to start over.

Optional: set `ACORN_FAILURE_EVENT_PATH=/path/to/events.jsonl` to receive
machine-readable JSONL events on every halt.
```

### 3.11 Summary of file changes

| File | Action | Approx. lines | Notes |
|---|---|---|---|
| `bin/acorn` | Add 3 env-var declarations | +3 | After `TELEGRAM_NOTIFY_URL` (line 10) |
| `bin/acorn` | Add 5 helpers (`stage_manifest`, `stage_name`, `validate_stage_artifacts`, `emit_failure_event`, `halt_pipeline_diagnostic`) | +180 | After `notify_foreman` (line 119) |
| `bin/acorn` | Add `cmd_internal` | +30 | Before `cmd_doctor` (line 3411) |
| `bin/acorn` | Add `_internal)` case in `main()` | +3 | Before `*)` catch-all (line 3683) |
| `bin/acorn` | Initialise `DOCTOR_FAIL=0`; add halt-scan loop in `cmd_doctor` | +14 | Drive-by fix + new feature |
| `bin/acorn` | Add halt prefix in `status_for_spec` (both return paths) | +6 | Lines ~1999–2037 |
| `bin/acorn` | Modify `planning_block_full` (sanitise + sed pipes + 6 stage gates + 1 bullet replacement) | ~+260 / ~−12 | Lines 673, 783, 1137, plus new gate insertions for stages 1–5 |
| `bin/acorn` | Modify `planning_block_lite` (4 gates + sanitise + sed + bullet) | ~+180 / ~−10 | Lines 1141, 1253, 1415 |
| `bin/acorn` | Modify `planning_block_quick` (2 gates + sanitise + sed + bullet) | ~+95 / ~−6 | Lines 1419, 1529, 1605 |
| `bin/acorn` | Patch `validate_prompt_md` placeholder lint | +5 | Lines 1672–1676 |
| `test/test_recon_completeness.sh` | New test file | ~+400 | All §6 tests |
| `claude/global/CLAUDE.md` | New "Failure Handling" section | +18 | Reference doc |
| `README.md` | New "Failure handling" subsection | +14 | User-facing doc |

**Total**: ~+1208 lines added, ~−28 lines removed across **4 files** (1 modified script, 1 new test, 2 narrative doc updates). Within the existing single-file architecture.

---

## 4. Data Models

### 4.1 Stage manifest format (in-memory only — emitted as text by `stage_manifest`)

One line per artifact, fields delimited by literal `|`:

```
<relative_path>|<grep -E header pattern>
```

`<relative_path>` is relative to the spec directory. `<grep -E header pattern>` is a regex passed to `grep -E -q`; `^## ` matches any markdown level-2 header, used to enforce "the file is structured markdown, not whitespace". Per AC #5, `architecture.md` requires the explicit literal `^## Directory Structure`.

### 4.2 HALT.md content schema (markdown file written to `<spec_dir>/<recon|plans>/HALT.md`)

```markdown
# Pipeline Halt: stage <N> (<stage_name>)

Halted at: 2026-05-02T14:33:11Z
Pipeline mode: lite
Spec slug: 2-sub-agent-failure-auto-retry-recon-completeness-ga
Repo: acorn
Stage: 0 (recon)
Failed agent: Agent A (Architecture & Structure)
Expected artifact: <spec>/recon/architecture.md
Observed: file missing
Retry budget: 1
Halt reason: artifact_missing

## Last 50 lines of agent output

```
(captured Task return text; "(no output captured)" if not provided)
```

## Suggested operator action

Run:

    acorn clean <repo> <slug> --yes
    acorn create <repo> <issue#> --<mode>

Or attach to the tmux session and ask the orchestrator to relaunch the failed agent:

    tmux attach -t <session_name>
```

`halt_reason` ∈ `{artifact_missing, artifact_empty, header_missing, retry_exhausted}`.

### 4.3 JSONL failure event schema (`ACORN_FAILURE_EVENT_PATH`)

One event per line. Forge configures `ACORN_FAILURE_EVENT_PATH=$HOME/.foreman/.foreman-events.jsonl`; upstream callers leave unset.

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
  "session_name": "acorn_specs_2-…_claude"
}
```

`event` is always the literal string `"subagent.halt"` (pinned in §3.3 `emit_failure_event`).

### 4.4 No persistent state changes

- No new tables, files, or schemas beyond HALT.md and the optional JSONL log.
- `meta.json` is read by `halt_pipeline_diagnostic` but never written.
- Existing spec directory layout unchanged; HALT.md is purely additive.

---

## 5. Error Handling

### 5.1 Layer A (orchestrator prompt) error contract

When `acorn _internal validate-stage` returns non-zero, stderr contains ONE LINE PER FAILED ARTIFACT, each of the form:

- `MISSING|<relpath>`
- `EMPTY|<relpath>`
- `HEADER|<relpath>|<pattern>`

The orchestrator parses these lines (one per failed agent) and relaunches all failed agents in a single Task batch. The mapping `relpath → agent` is enumerated explicitly in the planning block prompt text (§3.5.2 / §3.5.3 / §3.5.4) for each stage.

### 5.2 Layer B (bash helper) error semantics

| Helper | rc on success | rc on failure | Side effects |
|---|---|---|---|
| `stage_manifest` | 0 | dies (mode/stage unknown) | none |
| `stage_name` | 0 | always 0 (prints `unknown` for unknown) | none |
| `validate_stage_artifacts` | 0 | 1 (prints stderr lines) | none |
| `emit_failure_event` | 0 | 0 (best-effort) | appends JSONL if path set |
| `halt_pipeline_diagnostic` | always 1 | always 1 | writes HALT.md, prints stderr, calls emit_failure_event |
| `cmd_internal` | inherits sub | dies on bad sub or arg arity | per sub |

Conventions followed (per recon §"Conventions"):

- `set -euo pipefail` is in effect.
- `die()` reserved for fatal CLI errors (validation of arity, unknown subcommand, unsafe spec_dir).
- Helpers prefer `return 1` so callers decide whether to die.
- External-tool absences are tolerated (`command -v jq … || return 0`).
- Filesystem permission failures are wrapped (`2>/dev/null || true`).

### 5.3 Edge case handling

| Edge case | Behaviour | Where addressed |
|---|---|---|
| `ACORN_FAILURE_EVENT_PATH` parent dir missing | `mkdir -p` creates it; if mkdir fails, append silently dropped | §3.3 `emit_failure_event` |
| `ACORN_FAILURE_EVENT_PATH` unwritable / is a directory | Append fails silently (`>> "$path" 2>/dev/null \|\| true`) | §3.3 |
| `ACORN_FAILURE_EVENT_PATH` set but `jq` not installed | Helper returns 0 with no event written (`command -v jq` guard) | §3.3 |
| `ACORN_SUBAGENT_RETRY_BUDGET=0` | Orchestrator runs validate once, halts on first failure | §3.5.1 sanitisation passes 0 through; tested §6.11 |
| `ACORN_SUBAGENT_RETRY_BUDGET=2` | Up to 2 retries (3 total attempts) | §3.5.1; tested §6.11 |
| `ACORN_SUBAGENT_RETRY_BUDGET=-1` or non-numeric | Sanitised to default `1` via case block | §3.5.1 |
| Stage 0 has 2 failures of 3 | `validate_stage_artifacts` emits 2 stderr lines; orchestrator relaunches both in single Task batch | §3.2 (rc accumulator) |
| `meta.json` missing during halt | `jq -r '.slug // ""'` returns empty; HALT.md and event still written with empty fields | §3.3 |
| Spec dir on read-only filesystem | HALT.md write fails; full body dumped to stderr via `warn`; helper still returns 1 | §3.3 |
| Header pattern on whitespace-only file | `grep -E -q '^## '` requires the literal `## ` prefix; fails if absent | §3.2 |
| File with only `## Directory Structure` and no body | Passes existence + non-empty + header. Pipeline advances. (Heuristic check, deeper validation deferred — see §10 R5) | §3.2; documented in Resolution Log §2.4 |
| Sub-agent writes typo'd path (e.g. `architechture.md`) | Validation flags MISSING for the expected path. Retry instructs agent (via verbatim original prompt) to use exact path | §3.5.2 |
| Triple-backticks in `agent_log_tail` | Sanitised to ` ~~~ ` before writing HALT.md (`${var//\`\`\`/~~~}`) | §3.3 |
| 30 s retry sleep triggers Foreman watchdog stall detection | Sentinel file `.retry-pending` touched before sleep, removed after; updates spec mtime | §3.5.2 |
| Concurrent `acorn create` runs both halting | JSONL appends are atomic for writes < `PIPE_BUF` (4096B); each event is < 1KB; safe | POSIX guarantee |
| Operator runs `acorn _internal halt` directly with arbitrary path | `cmd_internal halt` rejects spec_dir not under `$PROJECTS_DIR/*/main/.specs/*` (path-prefix check) | §3.4.1 |

### 5.4 Operational notes (no code change)

| Note | Reason |
|---|---|
| When running `acorn create --no-auto`, operator must approve each `acorn _internal validate-stage` Bash call | `--no-auto` runs Claude WITHOUT `--dangerously-skip-permissions`; Bash tool prompts the user. Auto-trigger flow (default) is unaffected. |
| `ACORN_FAILURE_EVENT_PATH` must not contain literal `\|` or `\\` | Used as-is in shell expansions. Operator-controlled value; documented in `claude/global/CLAUDE.md`. |
| `_internal` subcommand is undocumented but reachable | Operator misuse writes HALT.md / emits an event; `acorn clean` removes both. |

### 5.5 Backwards compatibility (AC #7)

When neither env var is set:

- `ACORN_SUBAGENT_RETRY_BUDGET=1` → exactly matches today's "If a sub-agent fails, relaunch it" instruction (1 retry).
- `ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS=30` → 30 s pause is new but invisible (no prior baseline since retries weren't formalised).
- `ACORN_FAILURE_EVENT_PATH=""` → no events emitted.
- HALT.md is a NEW additive artifact (existing flows that don't look for it are unaffected).
- `cmd_doctor` reporting `HALTED PIPELINE` and exiting non-zero is a NEW failure surface. Documented in §3.10 README. Existing CI consumers can grep stderr for `HALTED PIPELINE` and route appropriately. Per Validation §1 row 7, this is acceptable since `acorn doctor` is already an opt-in diagnostic.
- Watchdog interaction during 30s retry sleep: sentinel file `.retry-pending` (§3.5.2) keeps mtime fresh. Acceptable false-positive window: < 30 s.

No existing public CLI behaviour changes for callers who don't set the env vars or run `acorn doctor`.

---

## 6. Testing Strategy

All new tests live in `/home/agentdev/projects/acorn/main/test/test_recon_completeness.sh`, following the existing harness pattern (per recon §"Test File Patterns and Harness" and conventions §"Test Framework and Patterns").

### 6.0 Harness boilerplate

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
assert_eq() {
  local name="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then pass "$name"
  else fail "$name" "expected '$expected', got '$actual'"; fi
}
assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then pass "$name"
  else fail "$name" "expected to contain '$needle'"; fi
}
assert_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    fail "$name" "expected NOT to contain '$needle'"
  else pass "$name"; fi
}

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# Silence side effects
notify_telegram() { :; }
notify_foreman() { :; }

# Tests follow ...

printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
```

### 6.1 Unit tests for `stage_manifest`

| # | Test | Setup | Expected |
|---|---|---|---|
| 6.1.1 | `stage_manifest full 0` returns 3 lines | none | `wc -l` = 3 |
| 6.1.2 | Stage 0 manifest names architecture.md and `## Directory Structure` | none | grep both substrings |
| 6.1.3 | `stage_manifest full 4` uses `red_team_N.md` (with underscore) | none | grep `red_team_1.md`, NOT `redteam_1.md` |
| 6.1.4 | `stage_manifest lite 1` returns `plans/draft.md` | none | exact match |
| 6.1.5 | `stage_manifest lite 2` returns `plans/validation.md` | none | exact match |
| 6.1.6 | `stage_manifest quick 1` returns `plans/SPEC.md` | none | exact match |
| 6.1.7 | `stage_manifest invalid 99` calls die | none | rc != 0; stderr contains `[ERROR]` |
| 6.1.8 | `stage_name full 4` returns `red-team` | none | exact match |
| 6.1.9 | `stage_name lite 1` returns `drafting` | none | exact match |

### 6.2 Unit tests for `validate_stage_artifacts`

Setup helper:

```bash
make_recon() {
  local d="$1"
  mkdir -p "$d/recon"
  printf '## Directory Structure\nstuff\n' > "$d/recon/architecture.md"
  printf '## Files\nstuff\n' > "$d/recon/relevant_code.md"
  printf '## Style\nstuff\n' > "$d/recon/conventions.md"
}
```

| # | Test | Setup | Expected |
|---|---|---|---|
| 6.2.1 | All 3 recon files valid → rc 0 | `make_recon $tmp` | rc 0; no stderr |
| 6.2.2 | architecture.md missing → rc 1, stderr `MISSING|recon/architecture.md` | `make_recon`; `rm architecture.md` | rc 1; grep stderr |
| 6.2.3 | relevant_code.md empty → rc 1, stderr `EMPTY|recon/relevant_code.md` | `make_recon`; `: > relevant_code.md` | rc 1; grep stderr |
| 6.2.4 | architecture.md missing required header → rc 1, stderr `HEADER|recon/architecture.md|^## Directory Structure` | write file with only `## Other` | rc 1; grep stderr |
| 6.2.5 | Two failures in one call → BOTH stderr lines emitted | `make_recon`; `rm architecture.md`; `: > relevant_code.md` | rc 1; stderr contains BOTH `MISSING\|...architecture.md` AND `EMPTY\|...relevant_code.md` |
| 6.2.6 | Spec dir doesn't exist → rc 1, stderr `MISSING|<path>` | call with non-existent path | rc 1; grep stderr |
| 6.2.7 | Stage 1 lite — draft.md present → rc 0 | `mkdir -p plans; echo "## h" > plans/draft.md` | rc 0 |
| 6.2.8 | Stage 1 lite — draft.md missing → rc 1 `MISSING|plans/draft.md` | empty plans/ | rc 1 |
| 6.2.9 | Stage 4 full — only 3/4 redteams → rc 1 `MISSING|plans/red_team_4.md` | write red_team_1..3 | rc 1; specifically names `red_team_4.md` |

### 6.3 Unit tests for `emit_failure_event`

| # | Test | Setup | Expected |
|---|---|---|---|
| 6.3.1 | `ACORN_FAILURE_EVENT_PATH` unset → rc 0, no file written | unset env var; call helper | rc 0; no file |
| 6.3.2 | Path set → JSONL line appended | set path; call helper | file has 1 line |
| 6.3.3 | Event JSON parses → has `event` = `subagent.halt` | same as 6.3.2 | `jq -r .event` returns `subagent.halt` |
| 6.3.4 | Event has stage, slug, agent, retry_count fields | call with explicit args | `jq -r .stage` = 0; `.slug` matches; `.agent` matches |
| 6.3.5 | Multiple events appended → 2 lines, both valid JSON | call helper twice | `wc -l` = 2; both `jq` parse |
| 6.3.6 | Path parent dir doesn't exist → mkdir + write | path `$tmp/deep/nested/events.jsonl` | dir created, file written |
| 6.3.7 | Unwritable path → rc 0, no crash | path `/proc/foo.jsonl` | rc 0 |
| 6.3.8 | Non-numeric `retry_count` → sanitised to 0 | pass `"abc"` for retry_count | `jq -r .retry_count` = 0 |

### 6.4 Unit tests for `halt_pipeline_diagnostic`

| # | Test | Setup | Expected |
|---|---|---|---|
| 6.4.1 | Stage 0 → writes `recon/HALT.md` | call with stage=0 | `recon/HALT.md` exists |
| 6.4.2 | Stage 2 → writes `plans/HALT.md` | call with stage=2 | `plans/HALT.md` exists |
| 6.4.3 | HALT.md contains stage, agent, artifact, observed | call with explicit args | grep each |
| 6.4.4 | HALT.md contains recovery commands | call helper | grep `acorn clean`, `acorn create` |
| 6.4.5 | Returns rc 1 always | call helper | rc != 0 |
| 6.4.6 | Stderr contains `Pipeline halted`, `Failed agent`, `Recovery` | capture 2>&1 | grep each |
| 6.4.7 | Emits event when path set | export `ACORN_FAILURE_EVENT_PATH`; call | event file has new line |
| 6.4.8 | Reads slug/repo from meta.json | write meta.json; call helper | HALT.md grep slug, repo |
| 6.4.9 | meta.json missing → no crash, empty fields | no meta.json | HALT.md still written |
| 6.4.10 | `agent_log_tail` with triple-backticks → sanitised | pass arg containing ``` | HALT.md contains `~~~` not ``` |
| 6.4.11 | HALT.md write fails (read-only dir) → body dumped to stderr | `chmod 000` on stage_dir | stderr contains the full HALT body |

### 6.5 Integration tests via `_internal` CLI (subprocess)

These run `bin/acorn _internal …` as a child process to test dispatch:

| # | Test | Command | Expected |
|---|---|---|---|
| 6.5.1 | validate-stage success | `acorn _internal validate-stage <good_dir> lite 0` | rc 0 |
| 6.5.2 | validate-stage missing | `acorn _internal validate-stage <bad_dir> lite 0` | rc 1; stderr `MISSING|...` |
| 6.5.3 | halt writes HALT.md | `PROJECTS_DIR=<tmp> acorn _internal halt <good_spec_dir> lite 0 "Agent A" recon/architecture.md artifact_missing "file missing"` | rc 1; HALT.md exists |
| 6.5.4 | halt rejects unsafe path | `acorn _internal halt /etc/foo lite 0 "X" "y" z "w"` | rc 1 (die); stderr "Refusing halt" |
| 6.5.5 | stage-manifest full 0 | `acorn _internal stage-manifest full 0` | stdout 3 lines |
| 6.5.6 | Unknown subcommand | `acorn _internal foo` | rc 1; stderr `Unknown _internal subcommand` |
| 6.5.7 | `_internal` absent from `--help` | grep `acorn --help` | no `_internal` substring |

### 6.6 Behavioural / pattern-scanning tests on rendered planning blocks

```bash
for mode in full lite quick; do
  block="$(planning_block_$mode "/tmp/spec")"
  assert_contains "$mode: validate-stage referenced" "$block" \
    'acorn _internal validate-stage'
  assert_contains "$mode: retry budget surfaced" "$block" \
    'ACORN_SUBAGENT_RETRY_BUDGET'
  assert_contains "$mode: halt command referenced" "$block" \
    'acorn _internal halt'
  assert_contains "$mode: agent A mapping (Stage 0)" "$block" \
    'recon/architecture.md` → Agent A'
  assert_contains "$mode: __MODE__ substituted (literal mode in text)" \
    "$block" "validate-stage \"/tmp/spec\" $mode 0"
  assert_not_contains "$mode: no leftover __RETRY_BUDGET__" "$block" \
    '__RETRY_BUDGET__'
  assert_not_contains "$mode: no leftover __MODE__" "$block" '__MODE__'
done
```

### 6.7 Gate count tests per mode

```bash
block="$(planning_block_full /tmp/x)"
count=$(printf '%s' "$block" | grep -c 'acorn _internal validate-stage')
assert_eq "full: 6 validate-stage references" "$count" "6"

block="$(planning_block_lite /tmp/x)"
count=$(printf '%s' "$block" | grep -c 'acorn _internal validate-stage')
assert_eq "lite: 4 validate-stage references" "$count" "4"

block="$(planning_block_quick /tmp/x)"
count=$(printf '%s' "$block" | grep -c 'acorn _internal validate-stage')
assert_eq "quick: 2 validate-stage references" "$count" "2"
```

### 6.8 `cmd_doctor` halt detection (independent loop)

```bash
mkdir -p "$tmp/projects/acorn/main/.specs/halted-spec/recon"
echo "# Pipeline Halt: stage 0 (recon)" \
  > "$tmp/projects/acorn/main/.specs/halted-spec/recon/HALT.md"
echo '{"slug":"halted-spec","repo":"acorn"}' \
  > "$tmp/projects/acorn/main/.specs/halted-spec/meta.json"

# No tmux session at all — verifies the halt scan is independent of
# session state.
PROJECTS_DIR="$tmp/projects" out=$(cmd_doctor 2>&1) || true
assert_contains "doctor surfaces halt" "$out" "HALTED PIPELINE"
assert_contains "doctor cites HALT.md path" "$out" "halted-spec/recon/HALT.md"

# Both recon/HALT.md and plans/HALT.md present
mkdir -p "$tmp/projects/acorn/main/.specs/halted-spec/plans"
echo "# Pipeline Halt: stage 2" \
  > "$tmp/projects/acorn/main/.specs/halted-spec/plans/HALT.md"
out=$(PROJECTS_DIR="$tmp/projects" cmd_doctor 2>&1) || true
assert_contains "doctor reports recon halt" "$out" "halted-spec/recon/HALT.md"
assert_contains "doctor reports plans halt" "$out" "halted-spec/plans/HALT.md"
```

### 6.9 `status_for_spec` halt prefix tests (BOTH return paths)

```bash
spec="$tmp/projects/acorn/main/.specs/halted-spec"
mkdir -p "$spec/recon"
echo "# Halt" > "$spec/recon/HALT.md"

# Path A: label-found path
gh() { echo 'spec-in-progress'; }
export -f gh
out=$(status_for_spec "$spec")
assert_contains "label path: status prefixed [HALTED]" "$out" "[HALTED]"
unset -f gh

# Path B: fallback path (no label)
gh() { return 1; }
export -f gh
out=$(status_for_spec "$spec")
assert_contains "fallback path: status prefixed [HALTED]" "$out" "[HALTED]"
unset -f gh

# When NOT halted, no prefix appears
rm "$spec/recon/HALT.md"
out=$(status_for_spec "$spec")
assert_not_contains "no prefix when not halted" "$out" "[HALTED]"
```

### 6.10 End-to-end induced-failure test (AC #6)

This is the canonical AC #6 validator. It is synthetic at the bash-helper layer (per Validation §1 row 6) — pure-bash unit testing cannot drive the LLM orchestrator end-to-end. Manual smoke step in §7.1 Step 7 covers the live path.

```bash
# Build a spec directory under PROJECTS_DIR so the halt path-prefix check
# accepts it.
spec="$tmp/projects/acorn/main/.specs/halt-e2e"
mkdir -p "$spec/recon"
echo '{"slug":"halt-e2e","repo":"acorn","issue_number":2,"session_name":"x"}' \
  > "$spec/meta.json"

# Simulate Agent A "crash": only 2 of 3 recon files written.
echo "## Files" > "$spec/recon/relevant_code.md"
echo "## Style" > "$spec/recon/conventions.md"
# (architecture.md missing — Agent A crashed)

# 1) validate-stage detects the failure
events="$tmp/events.jsonl"
ACORN_FAILURE_EVENT_PATH="$events" PROJECTS_DIR="$tmp/projects" \
  "$ACORN_SCRIPT" _internal validate-stage "$spec" lite 0 \
  > "$tmp/stdout" 2> "$tmp/stderr" || rc=$?
assert_eq "validate-stage exits 1" "${rc:-0}" "1"
assert_contains "stderr names missing file" "$(<"$tmp/stderr")" \
  "MISSING|recon/architecture.md"

# 2) Simulate retry exhaustion → halt
ACORN_FAILURE_EVENT_PATH="$events" PROJECTS_DIR="$tmp/projects" \
  "$ACORN_SCRIPT" _internal halt "$spec" lite 0 \
    "Agent A (Architecture & Structure)" "recon/architecture.md" \
    artifact_missing "file missing" \
    > "$tmp/halt.out" 2> "$tmp/halt.err" || rc=$?
assert_eq "halt exits 1" "${rc:-0}" "1"

# 3) HALT.md written
[ -f "$spec/recon/HALT.md" ] && pass "HALT.md written" \
  || fail "HALT.md written" "missing"

# 4) SPEC.md NOT produced
[ ! -f "$spec/plans/SPEC.md" ] && pass "SPEC.md not produced" \
  || fail "SPEC.md not produced" "found unexpectedly"

# 5) Event emitted
[ -f "$events" ] && pass "event file exists" \
  || fail "event file exists" "missing"
event="$(<"$events")"
assert_contains "event subagent.halt" "$event" '"event":"subagent.halt"'
assert_contains "event stage 0" "$event" '"stage":0'
assert_contains "event artifact" "$event" '"artifact":"recon/architecture.md"'
assert_contains "event slug" "$event" '"slug":"halt-e2e"'
```

### 6.11 Backwards-compat smoke test (AC #7)

```bash
unset ACORN_SUBAGENT_RETRY_BUDGET ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS \
      ACORN_FAILURE_EVENT_PATH
block="$(planning_block_lite /tmp/x)"
assert_contains "default budget appears" "$block" "1 retries per agent"
assert_contains "default backoff appears" "$block" "30 seconds"
assert_contains "event-path display marks unset" "$block" "(unset"

# Non-numeric env vars → sanitised
ACORN_SUBAGENT_RETRY_BUDGET="abc" \
ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS="-5" \
  block="$(planning_block_lite /tmp/x)"
assert_contains "non-numeric budget falls back to 1" "$block" \
  "1 retries per agent"
assert_contains "negative backoff falls back to 30" "$block" "30 seconds"
```

### 6.12 `validate_prompt_md` placeholder lint

```bash
# Generate a real PROMPT.md via render_prompt_md → ensure no placeholders leak
out_tmp="$tmp/PROMPT.md"
render_prompt_md "title" "body" '{}' "$out_tmp" lite "$tmp/spec"
validate_prompt_md "$out_tmp" && pass "valid PROMPT.md accepted" \
  || fail "valid PROMPT.md accepted" "rejected unexpectedly"

# Manually inject a stale placeholder → must reject
echo "stale __RETRY_BUDGET__" >> "$out_tmp"
validate_prompt_md "$out_tmp" && fail "stale placeholder rejected" "accepted"\
  || pass "stale placeholder rejected"
```

### 6.13 `cmd_clean` removes HALT.md (regression test)

```bash
spec="$tmp/projects/acorn/main/.specs/clean-test"
mkdir -p "$spec/recon"
echo "# halt" > "$spec/recon/HALT.md"
# (call cmd_clean stub or invoke binary; require --yes for non-interactive)
PROJECTS_DIR="$tmp/projects" "$ACORN_SCRIPT" clean acorn clean-test --yes \
  > /dev/null 2>&1 || true
[ ! -d "$spec" ] && pass "spec dir removed by clean" \
  || fail "spec dir removed by clean" "still present"
```

### 6.14 Existing tests must still pass

Run all existing tests after the patch:

```bash
for t in test/test_*.sh; do bash "$t" || exit 1; done
```

Particular attention:
- `test_auto_trigger.sh` — `wait_for_claude_ready`, `send_auto_trigger` unaffected.
- `test_doctor.sh` — extend with halt-detection assertions; existing assertions still pass.
- `test_path_npm_global.sh` — PATH handling unaffected.

### 6.15 Test execution (per existing convention)

No CI is configured in this repo (per recon §"CI/CD Configuration"). Tests are run manually:

```bash
bash test/test_recon_completeness.sh
INTEGRATION=1 bash test/test_recon_completeness.sh   # optional integration suite
```

Test file is bash 4+ (uses herestrings `<<<` and `$(<file)` — bashisms acceptable per recon §"Dependency Management").

### 6.16 Test data and fixtures

All test data is generated inline in `$TMPDIR_BASE` (per existing harness pattern). No external fixture files needed.

---

## 7. API Surface Summary

### 7.1 Public CLI (no changes)

Existing public commands (`acorn create`, `list`, `status`, `approve`, `clean`, `doctor`, `issue ...`, `deps ...`) gain NO new flags. Behaviour configured purely via env vars.

### 7.2 New env vars (configuration surface)

| Var | Default | Read by |
|---|---|---|
| `ACORN_SUBAGENT_RETRY_BUDGET` | `1` | `planning_block_*` (interpolated into PROMPT.md) |
| `ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS` | `30` | `planning_block_*` |
| `ACORN_FAILURE_EVENT_PATH` | `""` | `emit_failure_event`, `planning_block_*` (display only) |

### 7.3 New internal CLI (undocumented)

```
acorn _internal validate-stage <spec_dir> <mode> <stage>
acorn _internal halt           <spec_dir> <mode> <stage> <agent> <artifact> <halt_reason> <observed> [<agent_log_tail>]
acorn _internal emit-failure-event <slug> <stage> <stage_name> <agent> <artifact> <retry_count> <retry_budget> <halt_reason> <observed> <mode> <repo> <issue_number> <session_name>
acorn _internal stage-manifest <mode> <stage>
```

Not in `--help`. Tests assert absence (§6.5.7).

### 7.4 New internal bash functions

| Function | Inputs | Outputs | Side effects |
|---|---|---|---|
| `stage_manifest <mode> <stage>` | mode, stage int | stdout: `path\|header_pattern` lines | none |
| `stage_name <mode> <stage>` | mode, stage int | stdout: human label | none |
| `validate_stage_artifacts <spec_dir> <mode> <stage>` | spec dir, mode, stage int | rc 0 on success; rc 1 with multi-line stderr | none |
| `emit_failure_event` (13 args) | event metadata | rc 0 always | appends JSONL if `$ACORN_FAILURE_EVENT_PATH` set |
| `halt_pipeline_diagnostic` (7-8 args) | halt metadata + optional log tail | rc 1 always | writes HALT.md, prints stderr, calls `emit_failure_event` |
| `cmd_internal <sub> <args>` | subcommand + args | dispatches | per sub |

### 7.5 New artifacts on disk

| Artifact | Path | When written |
|---|---|---|
| `HALT.md` | `<spec>/recon/HALT.md` (stage 0) or `<spec>/plans/HALT.md` (stage > 0) | On retry exhaustion |
| `.retry-pending` | `<spec>/.retry-pending` | Touched before retry sleep, removed after (watchdog hint) |
| JSONL events | `$ACORN_FAILURE_EVENT_PATH` (operator-controlled) | Per halt, when env var set |

---

## 8. Implementation Order

Each step is independently verifiable. Land them as separate commits to preserve bisectability.

### 8.1 Sequence

**Step 1 — Add env vars and helper functions** (~+200 lines, additive)

1. Insert 3 env var declarations after `TELEGRAM_NOTIFY_URL` (line 10).
2. Insert `stage_manifest`, `stage_name`, `validate_stage_artifacts`, `emit_failure_event`, `halt_pipeline_diagnostic` after `notify_foreman` (line 119).
3. Insert `cmd_internal` before `cmd_doctor` (line 3411).
4. Insert `_internal)` case in `main()` BEFORE the `*)` catch-all (line 3683).

**Verification**:
- `bash test/test_recon_completeness.sh` (sections §6.1, §6.2, §6.3, §6.4 pass).
- `acorn _internal validate-stage` and `acorn _internal stage-manifest` work from CLI (§6.5).
- All existing tests still pass (`for t in test/test_*.sh; do bash "$t"; done`).

**Step 2 — `cmd_doctor` halt-scan loop + `DOCTOR_FAIL=0` init + `status_for_spec` halt prefix** (~+22 lines)

1. Initialise `DOCTOR_FAIL=0` at top of `cmd_doctor` (drive-by fix for latent `set -u` bug).
2. Add halt-scan loop (independent of session state) before the final `[ "$DOCTOR_FAIL" -ne 0 ]` check.
3. Patch `status_for_spec` to set `halted=1` and prefix BOTH return paths with `[HALTED] `.

**Verification**: §6.8, §6.9 pass. Existing `test_doctor.sh` still passes.

**Step 3 — `planning_block_quick` updates** (smallest blast radius)

1. Add header sanitisation + extended sed pipes (§3.5.1) at line 1421.
2. Replace Stage 0 confirm block (§3.5.2) at line 1529.
3. Insert Stage 1 single-agent gate (§3.5.4) after the Stage 1 final-spec instructions.
4. Replace orchestrator-context bullet at line 1605 (§3.5.5).

**Verification**:
- `planning_block_quick /tmp/x | grep -c 'acorn _internal validate-stage'` → 2.
- `planning_block_quick /tmp/x | grep -E '__RETRY_BUDGET__|__SPEC_PATH__|__MODE__'` → 0 lines.
- §6.6 (mode=quick), §6.7 (quick gate count) pass.

**Step 4 — `planning_block_lite` updates**

1. Same header changes as Step 3 at line 1143.
2. Replace Stage 0 confirm block at line 1253.
3. Insert Stage 1, Stage 2, Stage 3 single-agent gates (§3.5.4).
4. Replace orchestrator bullet at line 1415.

**Verification**: 4 validate-stage references; §6.6 (lite), §6.7 (lite count) pass.

**Step 5 — `planning_block_full` updates** (largest)

1. Header changes at line 675.
2. Replace Stage 0 confirm block at line 783.
3. Insert Stage 1 (multi-agent — §3.5.3) gate after the four drafter Task instructions.
4. Insert Stage 2, Stage 3 single-agent gates (§3.5.4).
5. Insert Stage 4 (multi-agent red-team — §3.5.3) gate.
6. Insert Stage 5 single-agent gate.
7. Replace orchestrator bullet at line 1137.

**Verification**: 6 validate-stage references; §6.6 (full), §6.7 (full count) pass.

**Step 6 — `validate_prompt_md` placeholder lint** (final, after planning blocks are clean)

This step MUST come AFTER Steps 3–5 (per Validation §3.13). Otherwise the lint will reject every PROMPT.md generated during the phased rollout.

1. Patch `validate_prompt_md` (§3.8).

**Verification**: §6.12 pass; full `acorn create acorn 2 --quick` end-to-end run succeeds.

**Step 7 — End-to-end + manual smoke**

1. Run §6.10 e2e test.
2. Manual smoke (live LLM): run `acorn create acorn 2 --quick` on a low-stakes test issue. Inspect rendered `PROMPT.md` to confirm gates appear with correct mode substitutions, no leftover `__VAR__` placeholders, and the agent-name → relpath mappings are present.
3. Manually delete one recon file mid-run after Stage 0 agents complete; observe orchestrator halts with HALT.md and `acorn doctor` reports `HALTED PIPELINE`.

**Step 8 — Documentation**

1. Update `claude/global/CLAUDE.md` (§3.10.1).
2. Update `README.md` (§3.10.2).

**Verification**: rendered docs read correctly.

### 8.2 Inter-step dependencies

```
Step 1 ──> Step 2 (DOCTOR_FAIL init must be in place before halt-scan adds DOCTOR_FAIL=1)
Step 1 ──> Step 3 (planning blocks call _internal helpers added in Step 1)
Step 3 ──> Step 4 ──> Step 5 (incremental rollout from smallest mode)
Step 5 ──> Step 6 (lint must come after all placeholders are introduced)
Step 6 ──> Step 7 (e2e validates the full chain)
Step 7 ──> Step 8 (docs reflect verified behaviour)
```

### 8.3 Rollback

Single bash file. If any step regresses:
- Revert the planning-block changes (Steps 3–5) — bash helpers (Steps 1–2) stay in place; they're inert without prompt-side calls.
- Existing in-flight specs (created before Step 5) keep working with their already-baked-in PROMPT.md.

### 8.4 Coexistence

- **Existing specs** (created before this change): PROMPT.md still has the old "Confirm all 3 files exist" text. Unchanged behaviour.
- **Forge consumers**: setting `ACORN_FAILURE_EVENT_PATH=$HOME/.foreman/.foreman-events.jsonl` starts producing `subagent.halt` events. No forge-side code change required.
- **Upstream callers** (no forge): leave `ACORN_FAILURE_EVENT_PATH` unset. Behaviour identical except for the new HALT.md artifact and stricter validation.

---

## 9. Acceptance Criteria → Test Mapping

| AC # | Implementation section | Test reference |
|---|---|---|
| 1 | §3.2 + §3.5 (gates after every stage) | §6.2 + §6.7 (gate counts per mode) |
| 2 | §3.1 env vars + §3.5 retry text | §6.6 (retry budget surfaced) + §6.11 (defaults) |
| 3 | §3.3 `halt_pipeline_diagnostic` + §4.2 HALT.md schema | §6.4 (HALT.md content + recovery) |
| 4 | §3.3 `emit_failure_event` + §4.3 JSONL schema | §6.3 + §6.10 (event emission e2e) |
| 5 | §3.2 (`^## Directory Structure` for stage 0 architecture.md) | §6.2.4 (header fail surfaces) |
| 6 | §6.10 synthetic e2e + §7.1 Step 7 manual smoke | §6.10 |
| 7 | §3.1 defaults + §5.5 BC analysis | §6.11 |

Every AC has a code path AND a test path. No AC is documentation-only.

---

## 10. Risk Register

Unresolved risks ranked by `severity × likelihood`. Resolved findings are in §2.

| ID | Risk | Severity | Likelihood | Mitigation |
|---|---|---|---|---|
| R1 | The orchestrator LLM ignores the new programmatic gate instructions | High | Medium | Instructions are MANDATORY-cased, monospaced, and reference the exact `acorn _internal validate-stage` command. Bash tool calls run with `--dangerously-skip-permissions` (auto-trigger mode). Behavioural tests verify prompt content; cannot verify LLM compliance — manual smoke test in first ~10 production runs (§7.1 Step 7). |
| R2 | The orchestrator interprets header-mismatch as "header check is wrong, file is fine" and proceeds anyway | Medium | Medium | Validation stderr emits machine-readable single lines per failure; prompt explicitly says "if exit code 1, do not advance, regardless of file contents." Header pattern is intentionally loose for non-architecture files; only architecture.md enforces a specific header. |
| R3 | Stage 0 with multiple parallel-agent failures — retry logic might miss agents | Medium | Low | `validate_stage_artifacts` accumulates ALL failures (§3.2) so orchestrator sees every failed file. Tested by §6.2.5 (two-failure case). |
| R4 | `ACORN_FAILURE_EVENT_PATH` unwritable produces no events without warning | Low | Low | Best-effort by design (matches `notify_foreman` semantics). Operator setup error. |
| R5 | Sub-agent succeeds (file written) but content is hallucinated/partial — header check passes | Medium | Medium | OUT OF SCOPE per AC #1 ("non-empty"). Existing red-team / validation stages catch some cases. Future work: LLM-as-judge content-quality check. Recommended follow-up issue listed in Resolution Log §2.4. |
| R6 | New planning block text grows PROMPT.md size, possibly exceeding context window | Low | Low | Added text ~+15–30%. Existing PROMPT.md is 1500–3000 lines; new total well within Claude context. Verified by length check. |
| R7 | Sed substitution misses an occurrence due to typo in placeholder name | Medium | Low | `validate_prompt_md` placeholder lint (§3.8) refuses any PROMPT.md containing `__SPEC_PATH__\|__RETRY_BUDGET__\|__RETRY_BACKOFF__\|__EVENT_PATH_DISPLAY__\|__MODE__`. Fail-loud at render time. |
| R8 | Forge JSONL consumer doesn't tolerate the new `subagent.halt` event | Low | Low | OUT OF SCOPE (forge is a separate repo). Forge already tolerates unknown event types. Coordinate with forge maintainer when this lands. |
| R9 | `cmd_doctor` flagging halts as DOCTOR_FAIL might break existing CI | Low | Medium | A halt IS a real failure — surfacing it is the goal. Documented in README §3.10.2. CI integrators can grep stderr for `HALTED PIPELINE`. |
| R10 | Operators may run `acorn clean` while still mid-triage on HALT.md | Low | Low | `acorn clean` is destructive by design; HALT.md is diagnostic and short-lived. Operator reads it before cleaning. |
| R11 | Concurrent retries write events out of order | Low | Low | JSONL append-only; writes < `PIPE_BUF` (4096B) atomic on POSIX. Each event < 1 KB. |
| R12 | `_internal` subcommand misused by operators directly | Very low | Very low | Misuse just writes a HALT.md / emits an event. `acorn clean` removes both. Path-prefix safety check (§3.4.1) prevents writes outside `$PROJECTS_DIR/*/main/.specs/*`. |
| R13 | Test sourcing the script (`eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"`) sensitive to new top-level env-var declarations | Low | Low | Existing pattern handles `VAR="${VAR:-default}"` lines. Verified manually in §7.1 Step 1 verification. |
| R14 | 30 s retry sleep flagged as stalled session by Foreman watchdog | Medium | Low | Sentinel file `.retry-pending` touched before sleep, removed after (§3.5.2). Bumps mtime; watchdog sees activity. |
| R15 | Operator sets `ACORN_FAILURE_EVENT_PATH` containing `\|` or `\\` (sed metachar) | Low | Very low | Operator-controlled value; documented in CLAUDE.md (§3.10.1). Sed substitution would corrupt PROMPT.md placeholder line; placeholder lint (R7) catches the resulting unexpanded text. |

### 10.1 Risks accepted explicitly

- R1, R5, R8, R14 are operational risks tied to LLM behaviour or external systems and accepted.
- R5 is the only AC-related deferral and is documented in §2.4 with a recommended follow-up issue.

---

## 11. Open Questions — All Resolved

Validation §8.1 listed 4 open questions. All are resolved in this spec:

1. **Custom manifest vs hard-coded `stage_manifest`?** Hard-coded. YAGNI; refactor when a 4th pipeline mode appears.
2. **Capture sub-agent log output for HALT.md?** Yes via optional 8th arg to `halt`; sub-agents return only "Done. Output: …" so the captured tail is usually short. Documented as partially-aspirational in §2.4.
3. **Retry budget per-agent or per-stage?** Per-agent (matches PROMPT.md AC #2 "retry that specific sub-agent once"). Locked in.
4. **Global pipeline timeout?** Out of scope. Existing watchdog/hang-detect handles session timeouts.

---

## 12. Definition of Done

All of the following must be true before merge:

- [ ] All §6 unit and integration tests pass (`bash test/test_recon_completeness.sh`).
- [ ] All existing tests still pass (`for t in test/test_*.sh; do bash "$t"; done`).
- [ ] Step 7 manual smoke test executed and outcomes documented in DONE.md.
- [ ] `claude/global/CLAUDE.md` and `README.md` updates landed.
- [ ] Rendered PROMPT.md for one full / one lite / one quick spec creation contains zero leftover `__VAR__` placeholders.
- [ ] `acorn doctor` reports `HALTED PIPELINE` and exits non-zero when a HALT.md exists.
- [ ] `acorn list` / `acorn status` show `[HALTED]` prefix for halted specs.
- [ ] No new pre-existing test regressions.
- [ ] Follow-up issue filed for content-quality validation (R5 deferral).

---

End of SPEC.





---

## Round-2 RT Review Notes (cross-model, manual pass 2026-05-02 — Wave 2 batch 1)

This SPEC was reviewed by an operator-driven manual cross-model RT pass on 2026-05-02 (Wave 2 of the SDLC review's compounding-foundation work) with **OpenAI GPT-5.4**, **Gemini gemini-pro-latest**, **DeepSeek V4 Pro** (reasoning), and **DeepSeek V4 Flash**. Full per-spec data: `docs/rt-experiment-data-cumulative.json` (key `wave_2_batch_1`).

**Wave 1 empirical context** (from the Wave 1 RT pass that produced 0 corroboration at Jaccard ≥0.4 across 21 findings on 3 specs): standard precondition-11 OR-merge would block this spec. Operator (strategist session) authorized continuation under the Wave 1 override pattern: findings are surfaced to Pi as guidance; Pi classifies and addresses during implementation; DONE.md must explicitly note disposition for each.

### Pi instruction for these findings

Read each finding below. Classify per your understanding of the spec scope and as-built code:

- **MUST-ADDRESS**: concrete defect you encounter or can clearly prevent during implementation. Address as additional AC. DONE.md must note how addressed (file:line).
- **ADVISORY**: improvement worth considering. Address if applicable; document choice in DONE.md.
- **SPECULATIVE**: speculative concern that may not apply to as-built code. Proceed without addressing unless concrete failure encountered. Note classification in DONE.md.

### Findings (raw, by model)


#### openai — verdict=flag, 3 findings, 14s, $0.0308, in/out=7376/823

**OP-1** [blocking]

> `halt_pipeline_diagnostic()` records the wrong retry count in emitted failure events. The function calls `emit_failure_event` with `${ACORN_SUBAGENT_RETRY_BUDGET:-1}` for both `retry_count` and `retry_budget`, so the JSONL output cannot distinguish 'halted after 0 retries', 'halted after 1 retry', etc. This contradicts AC #4's required `retry_count` field and makes the halt diagnostics/event stream materially inaccurate.

> **Suggested fix:** Change the interface so the actual retry attempt count is passed into `halt_pipeline_diagnostic` and then through to `emit_failure_event`. For example: update `halt_pipeline_diagnostic` signature to `... <halt_reason> <observed> <retry_count> [<agent_log_tail>]`, validate/sanitize `retry_count`, print it in HALT.md, and call `emit_failure_event "$slug" "$stage" "$sname" "$agent" "$artifact" "$retry_count" "${ACORN_SUBAGENT_RETRY_BUDGET:-1}" ...`. Update every rendered prompt block and any tests to supply the real retry count when invoking `acorn _internal halt`.

**OP-2** [blocking]

> The `_internal halt` path validation is too weak and can silently write `HALT.md` outside the intended spec directory via path traversal/symlinked input. The check only matches the raw string against `${PROJECTS_DIR%/}/*/main/.specs/*`, so a path like `$PROJECTS_DIR/repo/main/.specs/slug/../../other` or a symlink under `.specs` can satisfy the prefix pattern while resolving elsewhere. This violates the spec's stated safety fix for S2 and leaves a real arbitrary-write risk within the user's filesystem.

> **Suggested fix:** Canonicalize and verify the path before writing. In `cmd_internal halt`, resolve both `PROJECTS_DIR` and `spec_dir` with `realpath`/`readlink -f`, require that the resolved path exists and is a directory, then enforce a stricter shell pattern against the resolved absolute path, e.g. `resolved_projects=$(realpath "$PROJECTS_DIR")`; `resolved_sd=$(realpath "$sd") || die ...`; `case "$resolved_sd" in "$resolved_projects"/*/main/.specs/*) ;; *) die ... ;; esac`. Pass the resolved path to `halt_pipeline_diagnostic`.

**OP-3** [blocking]

> The spec claims AC #3 ('last 50 lines') is covered, but the implementation does not provide any mechanism in `bin/acorn` to capture or enforce the last 50 lines of agent output. `halt_pipeline_diagnostic` merely accepts an optional free-form `agent_log_tail` string from the orchestrator prompt, defaulting to `(no output captured)`. If the orchestrator omits it or supplies more/less than 50 lines, Acorn will still write HALT.md and tests can pass without verifying the required diagnostic content. This is an acceptance criterion that cannot be reliably verified by the described automated tests.

> **Suggested fix:** Move log-tail enforcement into the binary-facing interface. Add an `_internal halt-from-log <spec_dir> <mode> <stage> <agent> <artifact> <halt_reason> <observed> <log_path> [<retry_count>]` variant, or extend `_internal halt` to take a log file path instead of raw text; inside `bin/acorn`, verify the file exists/readable and compute `agent_log_tail="$(tail -n 50 -- "$log_path" 2>/dev/null || printf '(no output captured)')"`. Update prompt text to pass the actual agent log path, and update tests to assert HALT.md contains exactly the tailed content path-derived by the binary.



#### gemini — verdict=flag, 1 findings, 120s, $0.0113, in/out=8101/240

**GE-1** [blocking]

> In `validate_stage_artifacts`, if `stage_manifest` encounters an unrecognized mode or stage, it invokes `die`. However, because `stage_manifest` is executed inside a command substitution subshell `$(...)`, `die` only exits the subshell, not the parent script. The `manifest` variable becomes an empty string, causing the subsequent `while IFS='|' read...` loop to execute zero times. As a result, `validate_stage_artifacts` returns `rc=0` (success). This causes a silent failure where an invalid orchestrator request or unknown pipeline stage is incorrectly marked as fully validated, advancing the pipeline without any of the required artifacts.

> **Suggested fix:** Enforce the exit status of the subshell assignment. Change the manifest assignment to fail-fast: `manifest="$(stage_manifest "$mode" "$stage")" || return 1`.



#### deepseek-v4-pro — verdict=approve, 0 findings, 409s, $0.0366, reasoning=6931 tokens, in/out=7740/6660



#### deepseek-v4-flash — verdict=ERROR, 0 findings, 183s, $0.0016, in/out=7740/1803

  *Error:* findings JSON parse: Expecting value: line 1 column 1 (char 0)

### Override rationale

Standard precondition-11 cross-model verdict was `flag` (all four models flagged). Per Wave 1 empirical evidence (0% corroboration at Jaccard ≥0.4 across the model panel) and the SDLC review's classification protocol, findings are surfaced to Pi rather than blocking dispatch. Operator override authorized.
