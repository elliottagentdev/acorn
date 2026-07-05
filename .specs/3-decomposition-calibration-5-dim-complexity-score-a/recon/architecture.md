## Directory Structure

```
/home/agentdev/projects/elliottagentdev/acorn/
  bin/
    acorn                  # 4227-line single-file bash CLI (the entire application)
  test/
    test_split.sh          # Shell tests for split/decomposition functions
    test_auto_trigger.sh   # Shell tests for tmux auto-trigger
    test_approve_commit.sh
    test_auth_preflight.sh
    test_concurrent_launch.sh
    test_dependencies.sh
    test_doctor.sh
    test_idle_detect.sh
    test_idle_e2e.sh
    test_images.sh
    test_labels.sh
    test_notify.sh
    test_path_npm_global.sh
    test_planning_block_clarify.sh  # Tests planning_block_clarify (function NOT in live base)
    test_recon_completeness.sh
    test_rt_gate_removal.sh
    test_three_artifact.sh
  claude/
    commands/
      acorn.md             # /acorn slash command reference
    global/
      CLAUDE.md            # Global context for Claude about acorn
  .claude/
    skills/                # Acorn-internal skills
  evals/
    eval_set.json
    eval_set_acorn-issue-craft.json
    eval_set_acorn-spec-review.json
  .specs/                  # Spec output directory (managed by acorn)
    <slug>/
      PROMPT.md
      meta.json
      images/
      recon/
      plans/
  README.md
  UPSTREAM_PR.md
```

## Tech Stack

- **Language**: Pure bash shell script (`#!/usr/bin/env bash`, `set -euo pipefail`)
- **External runtime dependencies**:
  - `gh` (GitHub CLI) — fetches issues, manages labels, posts comments
  - `jq` — JSON parsing and construction
  - `tmux` — detached session management for Claude Code planning sessions
  - `claude` (Claude Code CLI) — runs multi-agent planning pipelines and one-shot analysis
  - `curl` — downloads images from GitHub issue bodies
  - `iconv`, `md5sum`/`md5`/`cksum` — slug generation and image hashing
- **No database, no server, no package.json, no Makefile** — the deployment artifact is the single bash file

## Architecture: Single-File Bash CLI

All logic resides in `/home/agentdev/projects/elliottagentdev/acorn/bin/acorn` (4227 lines).

### Top-Level Constants and Environment Variables (lines 1–27)

```bash
SCRIPT_NAME="acorn"
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"
LIFECYCLE_LABELS=(...)
TELEGRAM_NOTIFY_PORT="${TELEGRAM_NOTIFY_PORT:-8765}"
TELEGRAM_NOTIFY_URL="http://127.0.0.1:${TELEGRAM_NOTIFY_PORT}/notify"
ACORN_SUBAGENT_RETRY_BUDGET="${ACORN_SUBAGENT_RETRY_BUDGET:-1}"
ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS="${ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS:-30}"
ACORN_FAILURE_EVENT_PATH="${ACORN_FAILURE_EVENT_PATH:-}"
ACORN_OUTPUT_MODE="${ACORN_OUTPUT_MODE:-single}"
```

Pattern: all configurable values use `${VARNAME:-default}` at declaration, never bare magic numbers inside logic.

### Entry Point: `main()` (line 4092–4227)

Dispatches on `$1` (the command):

```
create      → cmd_create()
list        → cmd_list()
status      → cmd_status()
approve     → cmd_approve()
spec-complete → cmd_spec_complete()
doctor      → cmd_doctor()
setup-watchdog → cmd_setup_watchdog()
_internal   → cmd_internal()
watchdog-reset → ...
clean       → cmd_clean()
deps graph  → cmd_deps_graph()
issue create  → cmd_issue_create()
issue plan    → cmd_issue_plan()
issue clarify → cmd_issue_clarify()
issue label   → cmd_issue_label()
issue split   → cmd_issue_split()
issue depends → cmd_issue_depends()
```

### Key Commands (file paths and line numbers)

**`cmd_create()` (line 2448)**
Main pipeline entry. Flow:
1. Validates auth pre-flight and circuit breaker
2. Fetches GitHub issue JSON via `gh_issue_json()`
3. Builds slug: `<issue_number>-<slugified-title>`
4. Calls `render_prompt_md()` to generate `.specs/<slug>/PROMPT.md`
5. Creates tmux session via `start_session()`
6. Sends auto-trigger message via `send_auto_trigger()` using `auto_trigger_message()`
7. Writes `meta.json` via `write_meta_json()`

**`cmd_issue_plan()` (line 3757)**
Creates a GitHub issue then immediately calls `cmd_create()`. This is the "plan" workflow: no pre-existing issue required.

**`cmd_issue_split()` (line 3503)**
Manual decomposition command. Flow:
1. Fetches issue data
2. Calls `analyze_issue_for_split()` → returns JSON
3. Calls `format_split_recommendation()` to display to user
4. If `should_split=true` and `sub_count >= 2`, prompts user confirmation
5. Calls `create_sub_issues()` to create sub-issues on GitHub

### Spec Authoring Pipeline

**`render_prompt_md()` (line 1803)**
Generates PROMPT.md for a spec. Inserts:
1. Issue title/body
2. Discussion comments block
3. Planning methodology block (via `planning_block()`)
4. Optional three-artifact instructions
5. Completion protocol

**`planning_block()` (line 760)**
Dispatches to mode-specific function:
```bash
planning_block_full "$spec_path"   # line 771
planning_block_lite "$spec_path"   # line 1275
planning_block_quick "$spec_path"  # line 1581
```

Each function emits the methodology text as a heredoc with `sed` substitutions for `__SPEC_PATH__`, `__RETRY_BUDGET__`, `__RETRY_BACKOFF__`, `__EVENT_PATH_DISPLAY__`, `__MODE__`.

### Decomposition/Split Functions

**`analyze_issue_for_split()` (line 3208)**
- Args: `issue_title`, `issue_body`, `issue_comments`, `model`
- Uses `claude -p --model <model>` (one-shot headless) with a prompt asking for JSON
- JSON contract (MUST NOT be broken):
  ```json
  {
    "should_split": true|false,
    "reasoning": "...",
    "sub_issues": [
      {"title": "...", "scope": "..."},
      ...
    ]
  }
  ```
- Validates JSON structure with `jq -e 'has("should_split") and has("reasoning") and has("sub_issues")'`
- **Currently invoked ONLY by `cmd_issue_split()`** — NOT wired into spec-authoring path

**`format_split_recommendation()` (line 3299)**
Human-readable display of split analysis JSON.

**`create_sub_issues()` (line 3333)**
Creates GitHub sub-issues and posts a comment on the parent issue.

### Stage Management and Validation

**`stage_manifest()` (line 125)**
Returns expected artifacts for a given mode+stage:
```bash
full:0|lite:0|quick:0 → recon/architecture.md, recon/relevant_code.md, recon/conventions.md
full:1 → plans/draft_plan_1..4.md
full:2 → plans/evaluation.md
full:3 → plans/master_plan.md
full:4 → plans/red_team_1..4.md
full:5|lite:3|quick:1 → plans/SPEC.md
lite:1 → plans/draft.md
lite:2 → plans/validation.md
```

**`validate_stage_artifacts()` (line 162)**
Checks each expected artifact exists, is non-empty, and has required header.

**`cmd_internal()` (line 3901)**
Internal subcommands: `validate-stage`, `halt`, `emit-failure-event`, `stage-manifest`.

### Notification and Monitoring

- `notify_telegram()` (line 43) — fire-and-forget POST to Telegram bridge
- `notify_foreman()` (line 69) — fire-and-forget POST to Forged daemon (localhost:7700/notify-foreman)
- `check_circuit_breaker()` (line 219) — polls Forged status
- `register_with_forged()` (line 240) — registers session with Forged daemon

## Build and Deployment Model

- **No build step** — bin/acorn is executed directly
- **Deployment**: Copy bin/acorn to `~/acorn/bin/acorn` and/or `~/.foreman/bin/acorn`
- **Install path on PATH**: `/home/agentdev/.npm-global/bin` is prepended to PATH inside acorn (line 19), ensuring `claude` CLI resolves in non-interactive shells
- **Branch**: Feature work targets `forge-acorn-live-base` branch; no deploy to live during spec build
- **Git workflow**: `commit_spec_dir()` (line 2655) commits `.specs/<slug>/` on a target branch for dispatch

## Spec Directory Layout

```
$PROJECTS_DIR/<repo>/main/.specs/<slug>/
  PROMPT.md          # Requirements + planning methodology (generated once by cmd_create)
  meta.json          # {repo, issue_number, issue_title, slug, created_at, session_backend, session_name, mode, output_mode}
  images/            # Downloaded images from GitHub issue
  recon/
    architecture.md  # Stage 0 artifact
    relevant_code.md # Stage 0 artifact
    conventions.md   # Stage 0 artifact
    HALT.md          # Written on stage 0 failure
  plans/
    draft.md                  # lite:1
    validation.md             # lite:2
    draft_plan_1..4.md        # full:1
    evaluation.md             # full:2
    master_plan.md            # full:3
    red_team_1..4.md          # full:4
    SPEC.md                   # Final output (all modes)
    HALT.md                   # Written on planning stage failure
  DONE.md            # Written by implementation agent on completion
```

## Guardrail: Clarify Code Out of Scope

The test file `test/test_planning_block_clarify.sh` references a function `planning_block_clarify()` and `acorn _internal validate-stage "..." lite pre0`, but **this function does NOT exist in the current live base** (`bin/acorn` at commit d83a162). The function was removed/backed out. Per PROMPT requirements, clarify code must NOT be touched in this implementation.

## Existing Env-Variable Pattern for Thresholds

All env-overridable config follows this exact pattern (from lines 6–16 of bin/acorn):
```bash
VARNAME="${VARNAME:-default_value}"
```

New complexity thresholds must follow this same pattern. Suggested env var names (to be confirmed in planning):
```bash
ACORN_SCORE_HIGH_THRESHOLD="${ACORN_SCORE_HIGH_THRESHOLD:-12}"
ACORN_SCORE_MED_THRESHOLD="${ACORN_SCORE_MED_THRESHOLD:-8}"
ACORN_LOC_DECOMP_THRESHOLD="${ACORN_LOC_DECOMP_THRESHOLD:-800}"
ACORN_FILES_DECOMP_THRESHOLD="${ACORN_FILES_DECOMP_THRESHOLD:-8}"
```

## Test Infrastructure Pattern

All shell tests follow this exact pattern (from `test/test_split.sh`):

1. Source bin/acorn without running main: `eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"`
2. Override external dependencies (gh, claude, tmux, etc.) with bash functions
3. Use `pass()` / `fail()` helpers writing to PASS/FAIL counters
4. Use `assert_eq()`, `assert_contains()`, `assert_not_contains()` helpers
5. Setup/teardown via `mktemp -d` and `unset -f`
6. Exit `[ "$FAIL" -eq 0 ] || exit 1`

New tests for complexity scoring must fit this exact pattern. The test for the new feature should be `test/test_complexity_score.sh`.

## Summary: Minimal Touch Points for This Feature

The feature requires changes to:
1. **`bin/acorn`** only — add threshold env vars at top, new `score_spec_complexity()` function, wire into `render_prompt_md()` or the planning block, extend `analyze_issue_for_split()` JSON (additive), add decomposition proposal logic
2. **`test/test_complexity_score.sh`** (new file) — shell tests with negative controls

No other files need modification.
