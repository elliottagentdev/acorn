# Architecture Reconnaissance: Acorn

## Directory Structure

The acorn project lives in two locations on this machine (symlinked together):

```
/home/agentdev/acorn/           <- standalone clone (older, but identical content to main)
  bin/acorn                      <- actual script (3690 lines)
  README.md
  claude/
    commands/acorn.md
    global/CLAUDE.md
  evals/
    eval_set.json
    eval_set_acorn-issue-craft.json
    eval_set_acorn-spec-review.json
  test/
    acorn                        <- test helper
    test_auth_preflight.sh
    test_auto_trigger.sh
    test_concurrent_launch.sh
    test_dependencies.sh
    test_doctor.sh
    test_idle_detect.sh
    test_idle_e2e.sh
    test_images.sh
    test_labels.sh
    test_notify.sh
    test_path_npm_global.sh
    test_split.sh

/home/agentdev/projects/acorn/main/   <- worktree (identical content to /home/agentdev/acorn/)
  bin/acorn                             <- main script (3690 lines, same as above)
  README.md
  claude/
    commands/acorn.md
    global/CLAUDE.md
  evals/                                <- same eval sets
  test/                                 <- same tests

/home/agentdev/.local/bin/acorn        <- symlink -> /home/agentdev/acorn/bin/acorn
```

`/home/agentdev/.local/bin/acorn` is a symlink to `/home/agentdev/acorn/bin/acorn`. That file and `/home/agentdev/projects/acorn/main/bin/acorn` are identical (diff returns zero lines).

The spec directory for this issue is:
```
/home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/
  PROMPT.md
  meta.json
  images/           <- empty for this issue
  recon/
  plans/
```

## Tech Stack, Frameworks, and Languages

- **Language**: Pure Bash (`#!/usr/bin/env bash`), `set -euo pipefail`, `IFS=$'\n\t'`
- **No compiled code**: single file, no build step, no package manager
- **External dependencies**: `gh` (GitHub CLI), `jq` (JSON), `tmux` (session management), `claude` (Claude Code CLI), `curl` (HTTP/images), `python3` (doctor command)
- **Planning agents**: Claude Code (via `claude` CLI), orchestrated through tmux sessions; sub-agents are Claude Code Task tools (not separate processes)
- **Notification**: HTTP POST to a local Telegram bridge on port 8765 (configurable via `TELEGRAM_NOTIFY_PORT`); Foreman event bus at `localhost:7700`
- **No database**: state stored in filesystem (`.specs/<slug>/` directories with `meta.json`, `PROMPT.md`, recon files, plan files)

## Build System and Deployment Model

- **No build system**: the script is deployed by symlinking `bin/acorn` into a directory on `$PATH` (typically `/usr/local/bin/acorn` or `~/.local/bin/acorn`)
- **Installation**: `ln -s "$(pwd)/acorn/bin/acorn" /usr/local/bin/acorn` or via `/acorn-setup` Claude Code skill
- **The npm-global PATH export at line 14-16** ensures `claude` is found in non-interactive shells (e.g., Foreman background spawns):
  ```bash
  export PATH="/home/agentdev/.npm-global/bin${PATH:+:$PATH}"
  ```
- **No CI/CD config** found in the repository itself

## Key Entry Points and Main Modules

The entire logic lives in a single file: `/home/agentdev/projects/acorn/main/bin/acorn` (3690 lines).

### Execution flow

```
main()   (line 3559)
  -> argument dispatch (lines 3566-3688)
  -> cmd_create()   (line 2209) — primary command
  -> cmd_list()     (line 2352)
  -> cmd_status()   (line 2381)
  -> cmd_approve()  (line 2392)
  -> cmd_spec_complete()  (line 2434)
  -> cmd_clean()    (line 2471)
  -> cmd_doctor()   (line 3411)
  -> cmd_issue_create()   (line 3196)
  -> cmd_issue_plan()     (line 3267)
  -> cmd_issue_clarify()  (line 2951)
  -> cmd_issue_label()    (line 2983)
  -> cmd_issue_split()    (line 3013)
  -> cmd_issue_depends()  (line 3117)
  -> cmd_deps_graph()     (resolved via deps subcommand at ~line 3611)
  -> cmd_setup_watchdog() (line ~3280)
```

### Key helper functions

| Function | Line | Purpose |
|---|---|---|
| `planning_block()` | 662 | Dispatches to `planning_block_full/lite/quick` |
| `planning_block_full()` | 673 | Renders full 6-stage pipeline instructions into PROMPT.md |
| `planning_block_lite()` | 1141 | Renders lite 4-stage pipeline instructions into PROMPT.md |
| `planning_block_quick()` | 1419 | Renders quick 2-stage pipeline instructions into PROMPT.md |
| `render_prompt_md()` | 1621 | Assembles full PROMPT.md from issue body + planning block |
| `validate_prompt_md()` | 1672 | Checks PROMPT.md contains planning methodology anchor |
| `start_session()` | 1820 | Creates tmux session, launches `claude` |
| `send_auto_trigger()` | 1873 | Waits for Claude Code prompt, sends auto-trigger message |
| `wait_for_claude_ready()` | 1848 | Polls tmux pane for `> ` prompt pattern |
| `write_meta_json()` | 1948 | Writes `meta.json` with repo/issue/session metadata |
| `canonical_session_name()` | 268 | Converts `repo/specs/slug/claude` to tmux-safe name |
| `spec_dir()` | 227 | Returns `$PROJECTS_DIR/<repo>/main/.specs/<slug>` |
| `repo_main_path()` | 211 | Returns `$PROJECTS_DIR/<repo>/main` (worktree) or flat |
| `check_circuit_breaker()` | 121 | Queries Forged at `localhost:7700/status` for trip state |
| `register_with_forged()` | 142 | POSTs session registration to `localhost:7700/register` |
| `notify_telegram()` | 39 | Fire-and-forget POST to Telegram bridge |
| `notify_foreman()` | 65 | POSTs to Foreman event bus, falls back to Telegram |

## Pipeline Architecture

The pipeline is **prompt-embedded**: pipeline instructions are written into `PROMPT.md` at spec creation time (`cmd_create`). The Claude Code session reads `PROMPT.md` and acts as orchestrator; it uses the Claude Code `Task` tool to launch sub-agents.

### Pipeline modes and stage/agent counts

| Mode | Flag | Stages | Agent launches | Recon model | Planning model |
|---|---|---|---|---|---|
| Full | (default) | 6 (0-5) | 13 | Opus | Opus |
| Lite | `--lite` | 4 (0-3) | 6 | Sonnet | Opus |
| Quick | `--quick` | 2 (0-1) | 4 | Sonnet | Opus |

Note: README says "14 agents" for full mode (13 Task launches + orchestrator itself = 14 agents total).

### Stage 0 (Recon) — identical across all modes

All three modes launch **3 parallel Task agents** (architecture, relevant_code, conventions). Expected artifacts:
- `recon/architecture.md`
- `recon/relevant_code.md`
- `recon/conventions.md`

In full mode, recon agents use "opus" model. In lite and quick modes, they use "sonnet".

### Stage gate instruction (current, text-only)

After Stage 0 in all three pipeline blocks, the orchestrator receives this human-readable instruction:

> "After all 3 complete: Confirm all 3 files exist (...), then proceed to Stage 1. Do NOT read the files."

This is a **narrative instruction to the orchestrator LLM**, not a programmatic check. It relies on the orchestrator agent:
1. Understanding what "confirm" means
2. Actually calling file-existence tools
3. Halting on failure

**The critical line in `planning_block_full` at line 783**:
```
**After all 3 complete:** Confirm all 3 files exist (__SPEC_PATH__/recon/architecture.md, __SPEC_PATH__/recon/relevant_code.md, __SPEC_PATH__/recon/conventions.md), then proceed to Stage 1. Do NOT read the files.
```

Same pattern at line 1253 (lite) and line 1529 (quick).

**The critical line in `planning_block_full` at line 1137**:
```
- If a sub-agent fails, relaunch it. Do NOT do its work yourself as a fallback.
```

Same pattern at line 1415 (lite) and line 1605 (quick).

These are the two existing "manual" controls that the feature is formalizing into programmatic automation.

## Session Management Model

Acorn creates one tmux session per spec (`canonical_session_name()` returns e.g., `acorn_specs_2-sub-agent-failure-auto-retry-recon-completeness-ga_claude`). Claude Code runs inside this tmux session with `--dangerously-skip-permissions` (line 1837) when auto-trigger is enabled.

The session is **not acorn's own process** — it's a Claude Code session that reads PROMPT.md and orchestrates the planning pipeline itself. Acorn only:
1. Creates the tmux session
2. Sends the initial trigger message
3. Reports status via `cmd_status` / `cmd_doctor`

There is **no programmatic feedback loop** between the planning agents and the acorn bash script. The planning pipeline executes entirely within Claude Code's Task framework.

## External Integrations

### Foreman (forge-specific, optional)
- Auth pre-flight gate: `${FOREMAN_HOME:-$HOME/.foreman}/bin/auth-check.sh` (line 2237)
- Circuit breaker: `GET localhost:7700/status` → `.acorn_circuit_breaker.blocked` (line 121)
- Session registration: `POST localhost:7700/register` (line 142)
- Event notifications: `POST localhost:7700/notify-foreman` (line 103)
- Watchdog state: `${FOREMAN_HOME:-$HOME/.foreman}/watchdog-state/launch_<session>` (line 2322)
- Spec metadata extraction: `${FOREMAN_HOME}/bin/spec-metadata-extract.sh` (line 2418)
- Hang detection: `${FOREMAN_HOME}/bin/hang-detect.sh` (line 3415)
- Watchdog: `${FOREMAN_HOME}/bin/completion-watchdog.sh` (line 3343)

All Foreman integrations are **fail-open** — if Foreman is not running, the acorn command proceeds normally.

### Telegram bridge
- URL: `http://127.0.0.1:${TELEGRAM_NOTIFY_PORT:-8765}/notify`
- Used by: `notify_telegram()` — fire-and-forget, never blocks

### GitHub CLI (`gh`)
- Used for: issue fetch, label management, issue comments, status queries

## Spec Directory Layout

```
$PROJECTS_DIR/<repo>/main/.specs/<slug>/
  PROMPT.md             <- generated by cmd_create, contains planning instructions
  meta.json             <- {repo, issue_number, issue_title, slug, created_at, session_backend, session_name, mode}
  images/               <- downloaded images from GitHub issue (may be empty)
  recon/
    architecture.md     <- Stage 0 output (all modes)
    relevant_code.md    <- Stage 0 output (all modes)
    conventions.md      <- Stage 0 output (all modes)
  plans/
    draft_plan_1.md     <- Stage 1 output (full mode only)
    draft_plan_2.md     <- Stage 1 output (full mode only)
    draft_plan_3.md     <- Stage 1 output (full mode only)
    draft_plan_4.md     <- Stage 1 output (full mode only)
    evaluation.md       <- Stage 2 output (full mode only)
    master_plan.md      <- Stage 3 output (full mode only)
    red_team_1.md       <- Stage 4 output (full mode only)
    red_team_2.md       <- Stage 4 output (full mode only)
    red_team_3.md       <- Stage 4 output (full mode only)
    red_team_4.md       <- Stage 4 output (full mode only)
    draft.md            <- Stage 1 output (lite mode only)
    validation.md       <- Stage 2 output (lite mode only)
    SPEC.md             <- Final output (all modes — Stage 5/3/1 respectively)
  DONE.md               <- Written by implementing agent on completion (optional)
  metadata.json         <- Written by acorn approve + spec-metadata-extract.sh
```

## Global Configuration

- `PROJECTS_DIR`: default `$HOME/projects` — root of all project worktrees
- `TELEGRAM_NOTIFY_PORT`: default `8765`
- `TELEGRAM_NOTIFY_URL`: derived from above
- `FOREMAN_HOME`: default `$HOME/.foreman`
- No `ACORN_SUBAGENT_RETRY_BUDGET` or `ACORN_FAILURE_EVENT_PATH` env vars exist yet — these are the feature being implemented

## Error Handling in the Bash Script

- `set -euo pipefail` — any unhandled command failure exits immediately
- `die()` function: prints `[ERROR] ...` to stderr, `exit 1`
- `warn()` function: prints `[WARN] ...` to stderr, continues
- `info()` function: prints `[INFO] ...` to stdout, continues
- External calls use `|| true` or `|| warn ...` to soften failures
- `check_circuit_breaker()` is fail-open (line 127: `warn ... return 0` if curl fails)
- No retry logic exists in the bash layer for any operation

## No-Schema Data Layer

There is no database. All persistent state is filesystem:
- `meta.json`: written once by `cmd_create`, read by `cmd_list`, `cmd_status`, `cmd_clean`, `cmd_doctor`
- Lifecycle state: GitHub labels (not local files)
- Recon/plan artifacts: plain markdown files written by sub-agents
- Watchdog state: timestamp files in `~/.foreman/watchdog-state/`
- Event log: JSONL appended to `~/.foreman/logs/watchdog-events.jsonl`

## Relevant CI/Test Infrastructure

The test suite uses a pattern of **sourcing the acorn script with `main()` removed**:
```bash
eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"
```
This loads all functions into the test shell without executing `main()`. Tests then call functions directly and stub out external commands (`tmux`, `curl`, `gh`) with bash functions.

Test files:
- `/home/agentdev/projects/acorn/main/test/test_auto_trigger.sh` — tests `wait_for_claude_ready`, `send_auto_trigger`
- `/home/agentdev/projects/acorn/main/test/test_labels.sh` — tests label management
- `/home/agentdev/projects/acorn/main/test/test_images.sh` — tests image extraction/download
- `/home/agentdev/projects/acorn/main/test/test_dependencies.sh` — tests `get_blocked_by`, `add_blocked_by_dependency`
- `/home/agentdev/projects/acorn/main/test/test_path_npm_global.sh` — regression for PATH/claude resolution
- `/home/agentdev/projects/acorn/main/test/test_notify.sh` — tests `notify_telegram`
- `/home/agentdev/projects/acorn/main/test/test_split.sh`, `test_doctor.sh`, `test_idle_detect.sh`, `test_idle_e2e.sh`, `test_concurrent_launch.sh`, `test_auth_preflight.sh`

Unit tests use `INTEGRATION=1` flag to opt into tests that make real GitHub/tmux calls.

## Summary: Where the Feature Must Land

The feature is entirely in `/home/agentdev/projects/acorn/main/bin/acorn` (single bash file). No other files need modification for the core feature. New test file(s) in `test/` directory.

The feature touches:
1. **`planning_block_full()`** (line 673) — embed artifact validation after Stage 0 (line 783) and each subsequent stage
2. **`planning_block_lite()`** (line 1141) — same for lite pipeline (line 1253 and others)
3. **`planning_block_quick()`** (line 1419) — same for quick pipeline (line 1529)
4. Possibly new bash helper functions for: `validate_stage_artifacts()`, `emit_failure_event()`, `retry_subagent()`
5. New env vars read at script startup: `ACORN_SUBAGENT_RETRY_BUDGET` (default 1), `ACORN_FAILURE_EVENT_PATH` (default empty)

However, the pipeline orchestration is **prompt-driven inside Claude Code**, not bash-driven. The bash script only creates the tmux session and sends the initial trigger. The actual stage sequencing, sub-agent launches, and artifact verification happen inside the orchestrator LLM's execution context. Therefore, the feature implementation is primarily about:
- Adding programmatic artifact-checking instructions to the planning methodology blocks embedded in PROMPT.md
- OR adding a new bash-layer polling/validation loop that checks artifact presence after sessions complete

The PROMPT.md instructions currently say "confirm files exist" as human-readable text. Formalizing this means either strengthening the LLM instructions or adding bash-level checks.
