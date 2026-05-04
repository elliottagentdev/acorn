# Architecture Reconnaissance — Acorn Pipeline

## Project Overview

Acorn is a GitHub issue-to-spec pipeline tool. The entire project is a **single Bash script** (`bin/acorn`) plus a set of test shell scripts and Claude Code integration files (skills, commands, global CLAUDE.md). There is no compiled code, no package.json, no Python modules — just Bash.

**Repository root:** `/home/agentdev/projects/acorn/main/`

---

## Directory Layout

```
/home/agentdev/projects/acorn/main/
  bin/
    acorn                    # The ONLY executable — ~3700 lines of Bash
  test/
    test_auto_trigger.sh     # Tests: wait_for_claude_ready, send_auto_trigger
    test_concurrent_launch.sh
    test_dependencies.sh
    test_doctor.sh
    test_idle_detect.sh
    test_idle_e2e.sh
    test_images.sh           # Tests: extract_image_urls, generate_image_filename, etc.
    test_labels.sh           # Tests: lifecycle labels, clarification labels, status_for_spec
    test_notify.sh
    test_path_npm_global.sh
    test_split.sh            # Tests: analyze_issue_for_split, format_split_recommendation
    test_auth_preflight.sh
  claude/
    commands/acorn.md        # /acorn slash command definition for Claude Code
    global/CLAUDE.md         # Global Claude context injected into all sessions
  evals/
    eval_set.json
    eval_set_acorn-issue-craft.json
    eval_set_acorn-spec-review.json
  README.md
  .specs/
    <slug>/
      PROMPT.md              # Generated planning document with embedded methodology
      meta.json              # {repo, issue_number, slug, session_backend, session_name, mode}
      images/                # Downloaded images from GitHub issue
      recon/
        architecture.md      # Stage 0 output
        relevant_code.md     # Stage 0 output
        conventions.md       # Stage 0 output
      plans/
        draft.md             # Lite Stage 1 output
        validation.md        # Lite Stage 2 output
        draft_plan_{1..4}.md # Full Stage 1 output
        evaluation.md        # Full Stage 2 output
        master_plan.md       # Full Stage 3 output
        red_team_{1..4}.md   # Full Stage 4 output
        SPEC.md              # Final output (all modes)
```

---

## Tech Stack

- **Language:** Bash (bash 4+, `set -euo pipefail`, `IFS=$'\n\t'`)
- **Runtime dependencies:** `gh` (GitHub CLI), `jq`, `tmux`, `claude` (Claude Code CLI), `curl`, optionally `iconv`, `md5`/`md5sum`
- **No build system:** no Makefile, no package.json, no compiled artifacts
- **No database:** state is entirely in filesystem (`.specs/<slug>/meta.json`) and GitHub labels
- **No web framework:** no HTTP server in Acorn itself; it calls out to `http://localhost:7700` (Forged daemon) and `http://127.0.0.1:8765` (Telegram bridge) via `curl`

---

## Key Entry Points and Main Modules

### `bin/acorn` — the single entry point (lines 1–3691)

All logic lives in one file. Structure:

1. **Global constants and PATH setup** (lines 1–23)
   - `LIFECYCLE_LABELS`, `CLARIFICATION_LABELS`, `TELEGRAM_NOTIFY_PORT`
   - npm-global bin prepended to `PATH` for non-interactive shells

2. **Utility functions** (lines 25–660)
   - `info()`, `warn()`, `die()` — logging
   - `notify_telegram()`, `notify_foreman()` — fire-and-forget notifications
   - `check_circuit_breaker()` — queries Forged daemon at `localhost:7700/status`
   - `register_with_forged()` — registers session with Forged daemon
   - `repo_main_path()`, `spec_root()`, `spec_dir()` — path resolution
   - `slugify_title()`, `build_slug()` — slug generation (truncates at 50 chars)
   - `canonical_session_name()` — tmux session name: `<repo>_specs_<slug>_claude`
   - `gh_issue_json()` — fetches GitHub issue JSON
   - `ensure_labels()`, `set_issue_state_label()`, `set_clarification_label()` — GitHub label management
   - `comment_issue()` — posts GitHub comment
   - `gh_repo_nwo()` — resolves `owner/repo` from git remote
   - Dependency management: `get_blocked_by()`, `get_blocking()`, `add_blocked_by_dependency()`, `detect_circular_dependency()`, `topological_sort_waves()`

3. **Planning block generators** (lines 662–1607)
   - `planning_block()` — dispatcher
   - `planning_block_full()` — embeds full 6-stage pipeline instructions in PROMPT.md (uses heredoc with `__SPEC_PATH__` placeholder, replaced via `sed`)
   - `planning_block_lite()` — embeds lite 4-stage pipeline instructions (lines 1141–1417)
   - `planning_block_quick()` — embeds quick 2-stage pipeline instructions (lines 1419–1607)

4. **PROMPT.md rendering** (lines 1621–1676)
   - `render_prompt_md()` — assembles PROMPT.md: title + body + comments + planning_block() + completion protocol
   - `validate_prompt_md()` — checks for `PLANNING METHODOLOGY` anchor

5. **Image handling** (lines 1678–1818)
   - `extract_image_urls()` — extracts URLs from issue body+comments using regex
   - `extract_and_download_images()` — downloads to `images/` dir, returns mapping file
   - `rewrite_image_urls_in_text()` — rewrites URLs to local paths using bash string replacement

6. **Session management** (lines 1820–1972)
   - `start_session()` — creates detached tmux session, starts claude
   - `wait_for_claude_ready()` — polls tmux pane for `>` prompt up to 30s
   - `send_auto_trigger()` — sends planning message once Claude is ready (in background subshell)
   - `kill_session()` — kills tmux session
   - `write_meta_json()` — writes `{repo, issue_number, slug, session_backend, session_name, mode}` to `meta.json`

7. **Listing/display functions** (lines 1974–2208)
   - `status_for_spec()` — queries GitHub labels; falls back to filesystem (planning/review/unknown)
   - `clarification_for_issue()` — returns ai-drafted/clarified/-- based on GitHub labels
   - `print_list_header()`, `print_list_row()` — tabular output for `acorn list`
   - `list_specs_for_repo()`, `list_specs_all()` — iterates `.specs/` directories

8. **Command functions** (lines 2209–3557)
   - `cmd_create()` — main pipeline entry point
   - `cmd_list()` — `acorn list`
   - `cmd_status()` — `acorn status`
   - `cmd_approve()` — marks spec approved, writes `metadata.json` via Forged script
   - `cmd_spec_complete()` — marks `spec-review`, fires `notify_foreman(acorn.spec_ready)`
   - `cmd_clean()` — removes spec directory, kills session
   - `cmd_issue_create()`, `cmd_issue_plan()`, `cmd_issue_clarify()`, `cmd_issue_label()`, `cmd_issue_split()`, `cmd_issue_depends()`
   - `cmd_deps_graph()` — topological sort of issues
   - `cmd_setup_watchdog()` — installs cron/tmux watchdog
   - `cmd_doctor()` — checks running sessions for staleness

9. **main()** (lines 3559–3691) — command dispatcher

---

## Pipeline Modes and Output Files

The feature being planned adds PLAN.md and TASKS.md as new output artifacts alongside SPEC.md.

Current output structure per mode (all files live in `plans/`):
- **Full** (6 stages, 14 agents): `draft_plan_1.md`, `draft_plan_2.md`, `draft_plan_3.md`, `draft_plan_4.md`, `evaluation.md`, `master_plan.md`, `red_team_1.md`, `red_team_2.md`, `red_team_3.md`, `red_team_4.md`, `SPEC.md`
- **Lite** (4 stages, 6 agents): `draft.md`, `validation.md`, `SPEC.md`
- **Quick** (2 stages, 4 agents): `SPEC.md` only (from direct spec agent)

Target output for three-artifact mode (new):
- All above files PLUS: `PLAN.md`, `TASKS.md` (siblings of `SPEC.md` inside `plans/`)

---

## Configuration and Environment Variables

- `PROJECTS_DIR` — base directory for projects (default: `$HOME/projects`)
- `TELEGRAM_NOTIFY_PORT` — port for Telegram bridge (default: 8765)
- `FOREMAN_HOME` — path to foreman installation (default: `$HOME/.foreman`)
- `SESSION_NAME` — used in `notify_foreman()` fallback

**New variable required by this feature:**
- `ACORN_OUTPUT_MODE` — `single` (default, backwards-compat) or `three-artifact`

---

## How Planning Blocks Work (Key Mechanism)

The `planning_block_*()` functions generate the multi-agent orchestration instructions that get embedded in PROMPT.md. They use heredocs with `__SPEC_PATH__` replaced by `sed`:

```bash
planning_block_full() {
  local spec_path="${1:-.}"
  cat <<'METHODOLOGY_EOF' | sed "s|__SPEC_PATH__|${spec_path}|g"
  ... (entire orchestration instructions as a heredoc)
  METHODOLOGY_EOF
}
```

The final stage agent in each pipeline mode is given instructions to write SPEC.md to `__SPEC_PATH__/plans/SPEC.md`. For three-artifact mode, the same final-stage agent would need instructions to also produce PLAN.md and TASKS.md.

---

## cmd_approve and cmd_spec_complete — Relevant Checks

**`cmd_approve()`** (lines 2392–2432):
- Requires `plans/SPEC.md` to exist: `[ -f "$dir/plans/SPEC.md" ] || die`
- Sets GitHub label to `spec-approved`
- Calls external `spec-metadata-extract.sh` script from Forged to write `metadata.json`

**`cmd_spec_complete()`** (lines 2434–2469):
- Requires `plans/SPEC.md` to exist: `[ -f "$dir/plans/SPEC.md" ] || die`
- Sets GitHub label to `spec-review`
- Fires `notify_foreman("acorn.spec_ready", ...)`

Per the feature requirements, these should emit **warnings** (not errors) if `PLAN.md` or `TASKS.md` are absent when `ACORN_OUTPUT_MODE=three-artifact`.

---

## Test Infrastructure

All tests are shell scripts in `test/`. Each test file sources `bin/acorn` with `eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"` to load functions without invoking `main()`. Tests mock external tools (gh, tmux, claude) by re-exporting them as local Bash functions.

Test runner pattern:
- `pass()` / `fail()` / `assert_eq()` / `assert_contains()` / `assert_not_contains()`
- `INTEGRATION=1` flag enables tests that call real GitHub API
- Tests are run independently: `bash test/test_labels.sh`

**Relevant test files for the new feature:**
- `test/test_labels.sh` — tests for `cmd_approve`, `cmd_spec_complete` would go here or in a new `test_three_artifact.sh`
- `test/test_auto_trigger.sh` — tests `auto_trigger_message()` — relevant since the trigger message content may need updating

---

## Forged Integration Points

Acorn integrates with the Forged daemon (at `localhost:7700`) for:
- Circuit breaker check before `cmd_create`
- Session registration after launch
- Spec metadata extraction on `acorn approve` via `$FOREMAN_HOME/bin/spec-metadata-extract.sh`

The three-artifact feature should place PLAN.md/TASKS.md extraction logic in the Forged `spec-metadata-extract.sh` wrapper (not in the Acorn binary), per the "upstreamable design" constraint.

---

## Images

The `/home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/images/` directory exists but appears to contain no downloaded images (the issue had no image attachments).
