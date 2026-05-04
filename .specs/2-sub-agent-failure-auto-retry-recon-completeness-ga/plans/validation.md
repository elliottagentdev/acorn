# Plan Validation Report — Sub-agent failure auto-retry + recon completeness gate

Validated against:
- PROMPT.md acceptance criteria (7 criteria)
- Codebase reality (`/home/agentdev/projects/acorn/main/bin/acorn`, 3690 lines)
- Recon documents (architecture.md, relevant_code.md, conventions.md)

Validator role: identify (1) requirements coverage gaps, (2) factual errors, (3) ambiguities, (4) edge cases / risks.

Severity legend used throughout: **CRITICAL** (will block implementation or produce broken behaviour), **HIGH** (will require rework or mid-implementation question), **MEDIUM** (silent quality loss, deferred risk), **LOW** (polish / nit).

---

## 1. Requirements Coverage Matrix

| AC # | Requirement (verbatim from PROMPT.md) | Plan section addressing it | Testable? | Coverage assessment |
|---|---|---|---|---|
| 1 | Stage-completion validation: each stage's expected artifacts must exist AND be non-empty | §1.1, §3.4, §3.4.2 (gates inserted after every stage); `validate_stage_artifacts` in §3.2 | Yes — §6.2, §6.7 verify gate count per mode, §6.10 e2e | **COVERED with caveat**: gate text is repeated mechanically across 11 stage points but plan only shows the Stage 0 example verbatim. The other 10 gate insertion points are described as "[same retry / halt protocol as Stage 0]". This is a HIGH ambiguity for the implementer (see §3.1 below). |
| 2 | Per-agent retry, configurable via `ACORN_SUBAGENT_RETRY_BUDGET`, default 1, with backoff (default 30s); halt on retry exhaustion | §2.1 env vars; §3.4.2 retry protocol in prompt text; tests §6.11 | Partially — backwards-compat smoke test in §6.11 confirms defaults appear in rendered text, but no test confirms the orchestrator actually retries (because retry happens inside the LLM, not bash) | **COVERED at the prompt level**. The plan acknowledges this gap (§1.3 "Alternative considered: Wrap the tmux session in a polling bash loop — Rejected"). Acceptable, but operational verification will require manual smoke testing. |
| 3 | Halt with diagnostics: stage, sub-agent, expected vs observed, last 50 lines of agent output, suggested operator action | §2.3 HALT.md format; §3.2 `halt_pipeline_diagnostic`; §5.4 mapping table | Yes — §6.4 unit tests | **COVERED** for stage/agent/expected/observed/suggested action. **PARTIAL** for "last 50 lines" — plan §8 R-2 (open questions §8.1.2) explicitly admits this is "mostly aspirational" because sub-agents return only "Done. Output: …". This is a MEDIUM gap that should be acknowledged in SPEC.md as a deferred concern. |
| 4 | Optional event emission via `ACORN_FAILURE_EVENT_PATH`, JSONL with timestamp, slug, stage, agent, artifact, retry_count, halt_reason | §2.4 schema; §3.2 `emit_failure_event`; §6.3 tests | Yes | **COVERED + EXTENDED**. The plan's schema includes more fields than the PROMPT.md mandates (repo, issue_number, mode, stage_name, retry_budget, observed, session_name). All required fields are present. |
| 5 | Recon completeness gate: existence + non-empty + section headers (e.g., "## Directory Structure" in architecture.md) | §2.2 stage_manifest; §3.4.2 gate text; §6.2 tests | Yes | **COVERED**. The plan enforces `^## Directory Structure` for architecture.md and `^## ` (any header) for the other two. |
| 6 | Test: induce Stage 0 sub-agent crash; verify halt + diagnostic + no SPEC.md + event emitted | §6.10 end-to-end test | Yes | **COVERED but synthetic**. The plan §6.10 simulates a crash by manually omitting one recon file rather than killing a Task subprocess. This is a fair approximation given the LLM-driven orchestrator, but it does NOT exercise the actual orchestrator's retry-then-halt logic — only the bash helpers. The PROMPT.md wording "kill the Task subprocess" is not literally satisfied. **HIGH gap** the spec should explicitly flag and either (a) accept the limitation or (b) add a manual integration test step. |
| 7 | Backwards compatibility: callers not setting retry env var get current behaviour with 1 silent retry | §2.1 defaults; §5.5; §6.11 | Yes | **COVERED**. Default values match. However the plan introduces NEW behaviour (HALT.md artifact, `cmd_doctor` flagging halts as DOCTOR_FAIL) without flagging that existing CI consumers of `acorn doctor` may now exit non-zero on halts where previously they exited zero. Plan acknowledges in R9 but does not propose a fallback flag. **LOW** but worth noting in SPEC.md release notes. |

### 1.1 Missing in plan (constraint coverage)

| Constraint (from PROMPT.md §Constraints) | Plan coverage |
|---|---|
| "Retry budget configurable; sane default (1 retry) preserves current behavior" | COVERED §2.1 |
| "No forge-specific dependencies in the Acorn binary; failure events optionally emit to a configurable target" | COVERED §2.4 — no hard dependency on Foreman |
| "Fail-loud philosophy is universally beneficial" | COVERED §3.4.2 (HALT.md, stderr diagnostics) |

All three constraints are addressed.

---

## 2. Codebase Fact-Check

### 2.1 Verified facts (plan claims match codebase)

| Plan claim | Verified at | Status |
|---|---|---|
| Single bash file, 3690 lines | `wc -l bin/acorn` → 3690 | OK |
| `set -euo pipefail`, `IFS=$'\n\t'` at top | bin/acorn:2-3 | OK |
| `info`, `warn`, `die` at lines 35-37 | bin/acorn:35-37 | OK |
| `notify_foreman` at line 65-119 | bin/acorn:65 (function start) | OK |
| `check_circuit_breaker` at line 121-140 | bin/acorn:121 | OK |
| `planning_block` router at line 662-671 | bin/acorn:662-671 | OK |
| `planning_block_full` line 673 | bin/acorn:673 | OK |
| `planning_block_lite` line 1141 | bin/acorn:1141 | OK |
| `planning_block_quick` line 1419 | bin/acorn:1419 | OK |
| Stage 0 "Confirm all 3 files exist" at lines 783, 1253, 1529/1530 | bin/acorn:783, 1253, 1529 | OK (quick is at 1529 not 1530) |
| Orchestrator "If a sub-agent fails, relaunch it" at lines 1137, 1415, 1605 | bin/acorn:1137, 1415, 1605 | OK |
| `validate_prompt_md` at lines 1672-1676 | bin/acorn:1672-1676 | OK |
| `cmd_doctor` at lines 3411-3557 | bin/acorn:3411-3557 | OK |
| `main()` at line 3559 | bin/acorn:3559 | OK |
| `cmd_approve` SPEC.md check at line 2403 | bin/acorn:2403 | OK |
| `write_meta_json` at lines 1948-1971 | bin/acorn:1948-1971 | OK |

### 2.2 Factual errors found

| # | Plan claim | Codebase reality | Severity | Required correction |
|---|---|---|---|---|
| F1 | Plan §2.2 stage_manifest uses `plans/redteam_1.md` … `plans/redteam_4.md` (no underscore between "red" and "team") | bin/acorn lines 983, 985, 1008, 1010, 1033, 1035, 1057, 1059, 1079 use `plans/red_team_1.md` through `plans/red_team_4.md` (with underscore) | **CRITICAL** | All 4 redteam entries in `stage_manifest full 4` must be `red_team_N.md` (with underscore). Otherwise the gate after Stage 4 will incorrectly report MISSING for all four red-team artifacts and the pipeline will halt every full-mode run. Verified by `grep -n "red_team_\|redteam_" bin/acorn`. |
| F2 | Plan §3.6 patches `status_for_spec` to "prefix the status with `[HALTED] `". The plan implies this is a single-line tweak. | `status_for_spec` (lines 1999-2037) has TWO return paths: (a) when an issue lifecycle label is found via `gh`, the function returns just the label name (e.g., `spec-in-progress`); (b) when no label is found, it returns one of `review`/`planning`/`unknown`. The plan only shows adding the `halted=1` flag and "prefix the status" but does not say where the prefix is applied. If applied only in the fallback path, halts on labelled issues are not surfaced. If applied in both paths, the lifecycle label semantics are altered. | **HIGH** | Spec must specify: prefix `[HALTED] ` to BOTH return paths so the prefix is uniform. Tests must cover both label-present and label-absent paths. |
| F3 | Plan §3.5 references existing `DOCTOR_FAIL` flag pattern at "lines 3535, 3539". | `DOCTOR_FAIL` is referenced at lines 3535 (`DOCTOR_FAIL=1`) and 3539 (`[ "$DOCTOR_FAIL" -ne 0 ]`). It is **never initialized** anywhere in the file. With `set -u`, reading `$DOCTOR_FAIL` before it is set will exit the script. Verified by `grep -n "DOCTOR_FAIL" bin/acorn` (only those two lines). | **HIGH** (pre-existing latent bug, but the plan inherits it) | Plan §3.5 adds another `DOCTOR_FAIL=1` assignment in the per-spec loop; that assignment runs before the line 3539 read, so in practice the bug is masked. But if `cmd_doctor` is run with no halts (so the §3.5 patch never sets the flag) AND no notification port misconfig (so line 3535 also never sets it), then line 3539 fails under `set -u`. Plan should either (a) initialize `DOCTOR_FAIL=0` at the top of `cmd_doctor`, or (b) use `${DOCTOR_FAIL:-0}` pattern. Recommendation: initialize once at top of `cmd_doctor` for cleanness. |
| F4 | Plan §3.3 says insert `_internal` case in `main()` dispatch (~line 3580). | `main()` dispatch case statement runs from line 3566 to line 3687, with the catch-all `*)` at line 3683-3686 calling `usage; die "Unknown command: $cmd"`. Plan does not explicitly say "before the `*)` catch-all", which an inattentive implementer might miss. | **LOW** | Spec should say "insert before the `*)` catch-all (currently lines 3683-3686)." |
| F5 | Plan §3.4.1 modifies the existing `sed "s|__SPEC_PATH__|...|g"` pipe to "extend the sed to also replace retry/event placeholders" using "multiple sed invocations rather than one with multiple `-e` flags". | This is fine, but: each function's sed invocation is on a single line (`cat <<'METHODOLOGY_EOF' | sed "s|__SPEC_PATH__|${spec_path}|g"`) at lines 675, 1143, 1421. Adding 3 more pipes turns these single lines into 4-line backslash-continued shell, which is still bash-correct but increases diff complexity. The recon §1.1 didn't mention this, but the convention is that sed is on the same physical line. | **LOW** | Spec should explicitly show the multi-line continuation or use a single sed with `-e` per substitution — both are valid; choose one and be consistent. |
| F6 | Plan §1.3 says "the existing acorn pipeline runs Claude with `--dangerously-skip-permissions`, so Bash tool invocations don't get prompts" | Verified — bin/acorn:1837 uses `--dangerously-skip-permissions` when auto-trigger is on (`tmux send-keys ... "claude --dangerously-skip-permissions"`). Plan claim correct. However: when auto_trigger=0 (`--no-auto` flag), the orchestrator runs without `--dangerously-skip-permissions` and Bash tool invocations would prompt the user. The plan's retry/halt flow assumes Bash tool calls succeed silently. | **MEDIUM** | Spec must address what happens when `--no-auto` is used. Recommendation: gates still work, but the operator must approve each `acorn _internal validate-stage` Bash invocation. Document this as an operational note, not a code change. |
| F7 | Plan §3.7 says `cmd_clean` already does `rm -rf` on the spec directory; HALT.md is removed automatically. | bin/acorn:2471-2576 — yes, `cmd_clean` removes the spec dir. Plan claim correct. | OK |
| F8 | Plan §6.10 e2e test invokes `"$ACORN_SCRIPT" _internal validate-stage`. | The acorn script is sourced by the test harness via `eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"`. After this eval, `main()` is stripped, so subprocess invocations of `$ACORN_SCRIPT` are independent. Plan invokes the binary as a child process — this is fine, as long as the parent test sets the env vars in the child's environment. | OK (but see ambiguity §3.5) |
| F9 | Plan §3.4.2 instructs the orchestrator that "the relaunch prompt MUST be the original prompt verbatim". | The original Stage 0 sub-agent prompts are embedded in the `planning_block_*` heredocs. The orchestrator does not have the prompts as a separate variable — it has them inline in PROMPT.md. The instruction implies "use the same prompt text" which is reasonable, but the orchestrator may copy-paste imperfectly. | **MEDIUM** | Spec should clarify what "verbatim" means here — likely "the same prompt block from the methodology section, unchanged". Optional improvement: include the agent prompts in named anchors that the retry instructions can reference. |
| F10 | Plan §2.1 declares three new env vars at top of `bin/acorn`. The `ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS` is mentioned in §2.1 (default 30) but PROMPT.md acceptance criterion #2 only requires one env var (`ACORN_SUBAGENT_RETRY_BUDGET`) and refers to "backoff (default 30s)" without naming the env var. | The plan's choice to expose the backoff as a separate env var is a minor scope expansion. | **LOW** | Either keep it (it's a sensible addition, follows convention) or hard-code 30s. Spec must commit one way; tests must reflect the choice. |

### 2.3 Reused-vs-reinvented audit

| Existing utility | Plan's reuse choice | Verdict |
|---|---|---|
| `info`, `warn`, `die` | Reused (§5.2) | OK |
| `notify_foreman` JSONL pattern | NOT reused for `emit_failure_event`; recon §3 explicitly says "should NOT reuse this function — it appends to a file instead of posting to an HTTP endpoint" | OK — different transport, different code path is appropriate |
| `write_meta_json` jq -n pattern | Reused for `emit_failure_event` (similar `jq -nc` with `--arg`/`--argjson` flags) | OK |
| `validate_prompt_md` (existing return-1 pattern) | Reused as a structural template for `validate_stage_artifacts` | OK |
| `wait_for_claude_ready` retry loop pattern | NOT directly reused (the new retry happens at the prompt level inside the LLM, not in bash) | OK — different layer |
| `set +e ... ec=$? ... set -e` pattern for fallible external calls | Not explicitly used in new helpers because the helpers themselves ARE the fallible calls; callers (orchestrator) check exit codes | OK |
| `[ -f path ]`, `[ -s path ]`, `grep -E -q PATTERN file` checks | Reused in `validate_stage_artifacts` | OK |
| `mkdir -p $(dirname …) 2>/dev/null \|\| true` | New idiom in `emit_failure_event` (§3.2). Acceptable but not previously seen in this script. | OK |
| Test harness pattern (`eval "$(sed '/^main "\$@"/d')"`) | Reused in §6 | OK |

No utilities are reinvented. Choice of new function names (`stage_manifest`, `stage_name`, `validate_stage_artifacts`, `emit_failure_event`, `halt_pipeline_diagnostic`) does not collide with existing names — verified by `grep -n "^stage_manifest\|^stage_name\|^validate_stage_artifacts\|^emit_failure_event\|^halt_pipeline_diagnostic" bin/acorn` returns no matches.

---

## 3. Ambiguity Audit

### 3.1 §3.4.2 — Stage gates beyond Stage 0

The plan provides full gate text for Stage 0 (~50 lines) and a one-paragraph Stage 1 sketch ("[same retry / halt protocol as Stage 0]"). It then says "The same template is repeated for every subsequent stage … Total of 11 stage-completion gates inserted."

**What's missing for the implementer:**

- The exact agent-name → relpath mapping for Stage 1+ stages. For Stage 0, the plan names "Agent A (Architecture & Structure) ↔ architecture.md". For Stage 1 full mode (4 parallel drafts), how is each draft mapped to which "Agent"? The recon §"Pipeline Architecture" doesn't enumerate agent identifiers per stage. **HIGH ambiguity** — implementer will guess names that may not match the orchestrator's understanding.
- For sequential single-agent stages (Stage 2 evaluation, Stage 3 synthesis, Stage 5 final-spec, lite Stages 1/2/3, quick Stage 1) the "ALL failed agents in parallel" text from Stage 0 is irrelevant. The gate text needs simplifying for these stages but plan does not show what.
- The sentence "Retry budget is __RETRY_BUDGET__ retries per agent" — for a single-agent stage with retry_budget=1, the orchestrator launches the agent, validates, and on failure retries once. Clear. For Stage 0 / Stage 1 / Stage 4 (parallel agents), "per agent" must be enforced or one heavy hitter could exhaust the budget while a fast one is still being retried. Plan §5.3 mentions this case but defers to "described explicitly in the planning-block prompt text". **MEDIUM ambiguity** — needs concrete prompt text in spec.

**Recommended resolution in spec:** Provide all 11 gate texts verbatim, not just the Stage 0 example. Yes, this is repetitive — but the existing planning blocks are similarly verbose, and the parallel/sequential variants need different text.

### 3.2 §3.4.1 — Placeholder substitution

Plan introduces `__RETRY_BUDGET__`, `__RETRY_BACKOFF__`, `__EVENT_PATH_DISPLAY__` placeholders. It says use multiple sed pipes:

```bash
cat <<'METHODOLOGY_EOF' \
  | sed "s|__SPEC_PATH__|${spec_path}|g" \
  | sed "s|__RETRY_BUDGET__|${retry_budget}|g" \
  | sed "s|__RETRY_BACKOFF__|${retry_backoff}|g" \
  | sed "s|__EVENT_PATH_DISPLAY__|${event_path_display}|g"
```

**Issues:**

- If `event_path_display` contains a `|` (the sed delimiter), substitution corrupts. `ACORN_FAILURE_EVENT_PATH=/some/path` is fine, but a value like `/log|file.jsonl` would break. **LOW** — unlikely in practice, but plan should note "delimiter-safe values only" or use a different delimiter for the event path sed.
- The original `__SPEC_PATH__` substitution is also vulnerable to `|` in the spec path. Pre-existing issue, not introduced here, but worth flagging.
- Plan §R7 proposes a lint check `grep -c '__RETRY_BUDGET__\|__RETRY_BACKOFF__\|__EVENT_PATH_DISPLAY__'` to detect unsubstituted placeholders. Good — but implementer must remember to add to `validate_prompt_md`. The §3 changes table mentions this (line 1094) but §3.4.1 does not. **LOW ambiguity**.

### 3.3 §3.6 — `status_for_spec` halt prefix path

(See F2 in §2.2.) Plan says "prefix the status with `[HALTED] `" but does not specify which return path. **HIGH ambiguity**.

### 3.4 §3.4.2 — `<MODE>` placeholder in gate text

The example gate text says:

> `acorn _internal validate-stage "__SPEC_PATH__" <MODE> 0`
> where <MODE> is `full`, `lite`, or `quick` matching this pipeline.

This is ambiguous: is the orchestrator expected to fill in `<MODE>` itself by reading the methodology header? Or should the plan template hard-code each mode at generation time so the rendered PROMPT.md says `acorn _internal validate-stage "/path/to/spec" lite 0` directly?

The latter is far more reliable. Plan §3.4.1 already adds sed pipes — adding `__MODE__` as a fourth placeholder substituted from the function name (`full`/`lite`/`quick`) is trivial. Otherwise the orchestrator may incorrectly substitute `<MODE>` (e.g., putting it literally as `<MODE>`).

**HIGH ambiguity** — recommend adding `__MODE__` substitution.

### 3.5 §6.10 — env var propagation in subprocess test

The §6.10 test runs the script as a subprocess (`"$ACORN_SCRIPT" _internal validate-stage …`). Bash inheritance: only **exported** vars propagate. Plan does not say whether `ACORN_FAILURE_EVENT_PATH=…` is prefix-style (single command env-var) or `export`-style. The existing harness sources acorn after stripping `main`, so functions inherit calling shell environment. For the subprocess invocation, prefix-style is cleanest:

```bash
ACORN_FAILURE_EVENT_PATH="$tmp/events.jsonl" \
  "$ACORN_SCRIPT" _internal validate-stage …
```

Plan shows this exact form. **LOW ambiguity** — implementer should not be confused, but spec should be explicit about not relying on `export`.

### 3.6 §2.1 — `ACORN_SUBAGENT_RETRY_BUDGET=0` semantics

Plan §5.3 says: "Orchestrator runs validate once, halts on first failure. Tested." So a budget of 0 means zero retries (one initial attempt only). This is correct semantically but implicitly assumes the orchestrator interprets "budget" as "retries beyond the first attempt" and not "total attempts". The PROMPT.md AC #2 says "retry that specific sub-agent once" with budget=1, which corresponds to "1 retry beyond the first" → 2 total attempts. Confirm semantics in spec. **LOW**.

### 3.7 §2.1 — Non-numeric / negative env var values

Plan §5.3 mentions "ACORN_SUBAGENT_RETRY_BUDGET=-1 or non-numeric → Treated as 1 (default). A `case` block in the helper ensures only digits". But §3.2 helper code shows no such case block — it uses `${retry_count:-0}` in `emit_failure_event` and passes the value through to `printf` / `sed`. **MEDIUM ambiguity**: need explicit input validation in `cmd_internal validate-stage`-related code or in `planning_block_*` (where the env var is read).

Recommendation: in the `planning_block_*` functions, sanitize the values before they're embedded in PROMPT.md:

```bash
local retry_budget="${ACORN_SUBAGENT_RETRY_BUDGET:-1}"
case "$retry_budget" in
  ''|*[!0-9]*) retry_budget=1 ;;
esac
```

### 3.8 §3.2 — `validate_stage_artifacts` exits on first failure

The function uses `return 1` inside the `while read` loop, so it exits on the first failed file. If both architecture.md and conventions.md are missing, only the first is reported. Orchestrator then relaunches Agent A only, validates, fails on Agent C, relaunches Agent C. This works but means a Stage 0 with multiple failures takes multiple rounds (each round = one validate + one relaunch + one validate).

**MEDIUM ambiguity**: The PROMPT.md gate text says "relaunch ALL failed agents in parallel" (recon §"Edge Cases" / plan §5.3), but the bash helper reports only one failure per call. The orchestrator must re-run validate-stage after each relaunch, OR the helper must report all failures.

Recommendation: change `validate_stage_artifacts` to accumulate failures and emit all of them (one stderr line per failure), returning 1 if any failed. Pseudo:

```bash
local rc=0
while IFS='|' read -r path header; do
  …
  if missing/empty/header_fail: printf '%s|%s\n' "$kind" "$path" >&2; rc=1
done
return $rc
```

This lets the orchestrator parse stderr once, identify all failed agents, and relaunch them in a single Task batch (matching Stage 0's "single message" parallel pattern).

### 3.9 §3.2 — `halt_pipeline_diagnostic` agent_log_tail format

Plan §3.2 accepts an optional 8th positional arg `agent_log_tail` and embeds it inside a triple-backtick block. If the tail itself contains triple-backticks, the markdown breaks. **LOW** — but spec should note "agent_log_tail must be sanitized of triple-backticks or use a different fence (e.g., `~~~`)."

### 3.10 §3.4.2 — "verbatim" relaunch prompt

(See F9 in §2.2.) "The relaunch prompt MUST be the original prompt verbatim" is ambiguous — original from where? The orchestrator does have the prompt in PROMPT.md. **MEDIUM** — spec should say "use the same Agent A/B/C prompt block defined earlier in this methodology section, unchanged."

### 3.11 §3.5 — `cmd_doctor` halt loop scope

Plan §3.5 says "add a halt-detection check inside the existing `cmd_doctor` per-spec loop". The existing loop runs only if a session is `running` and a meta.json exists. **HALTED** specs may have:
- meta.json present (created at spec creation)
- Tmux session may have exited or be dead → `session_state` returns not-`running` → the `[ "$state" = "running" ] || continue` check at line 3458 SKIPS the iteration

So a HALT.md in a non-running session would not be detected with plan's patch. **HIGH ambiguity** — placement of the patch matters. Either:
- Move the halt check before the `state` check
- Add a separate scan loop for HALT.md across all spec dirs (independent of session state)

The latter is cleaner and surfaces orphaned halts after operators kill the tmux session.

### 3.12 §6.10 — How to assert SPEC.md is "not produced"

The test asserts `[ ! -f "$tmp/spec/plans/SPEC.md" ]` after the simulated halt. But the simulated halt is just calling validate-stage and halt manually — neither command would have written SPEC.md anyway. The test thus does not really verify SPEC.md non-production; it verifies that bash helpers don't write SPEC.md, which is trivially true.

**MEDIUM ambiguity**: For AC #6 to be meaningfully tested, the spec must either (a) accept the limitation explicitly and reword the test to check "the recon stage halt prevents stage advancement at the prompt level" (manual smoke), or (b) build a lightweight harness that mocks Task and tracks whether subsequent stages would have been entered.

### 3.13 §7 — Order-of-operations dependencies between steps

Plan §7.1 shows 7 implementation steps. Step 1 adds bash helpers; Step 2 patches doctor/status; Steps 3-5 modify planning blocks. Critical dependency NOT stated:

- The `validate_prompt_md` placeholder lint added in §3.4.1 / Risk R7 / changes table line 1094 must run AFTER all `__RETRY_*` placeholders are added to the heredocs (Steps 3-5). If the lint is added in Step 1, all spec creations in Steps 1-2 will fail because nothing has substituted the new placeholders yet. **HIGH ordering risk**.

Resolution: add the lint check LAST (after Step 5) or make the lint recognize the new placeholders as expected/optional.

---

## 4. Edge Cases & Risks

### 4.1 Edge cases NOT covered by the plan

| # | Edge case | Plan handling | Severity |
|---|---|---|---|
| E1 | Spec dir on read-only filesystem during halt | Plan §5.3 says "HALT.md write fails silently; warn() still prints to stderr; orchestrator still STOPs (because halt rc is 1)". Acceptable. But the failure event also fails to append. Operator has neither HALT.md nor JSONL trail. **MEDIUM**. Recommend: in `halt_pipeline_diagnostic`, if HALT.md write fails, use `warn` to print the entire HALT.md content to stderr so operator can capture from logs. | MEDIUM |
| E2 | `ACORN_FAILURE_EVENT_PATH` set to a directory (typo) | `printf '%s\n' "$payload" >> "$dir/"` fails with `Is a directory`. Plan §5.3 row 1 covers `mkdir -p` of parent, but doesn't address path-is-directory. `>> "$path" 2>/dev/null \|\| true` swallows the error. **LOW** — silent best-effort, consistent with notify_foreman semantics. | LOW |
| E3 | Two parallel `acorn create` runs both halting at the same instant, both writing to `ACORN_FAILURE_EVENT_PATH` | Plan §R11 covers this: "JSONL is append-only with `>>`; on most filesystems writes < PIPE_BUF (4096B) are atomic. Each event is < 1KB." OK. But `mkdir -p` race is not covered — concurrent mkdir is safe (POSIX `-p` is idempotent). | OK |
| E4 | Sub-agent succeeds but Task tool returns an error message about the agent | Validation passes (file exists), but the orchestrator's Task return string indicates a problem. Currently no mechanism to flag this. Plan does not address. | LOW (out of scope; recon §3 confirms this is a future concern) |
| E5 | `meta.json` written but contains corrupt JSON | `jq -r '.slug // ""' meta.json 2>/dev/null \|\| true` returns empty. HALT.md is written with empty fields. Event emitted with empty fields. Plan §5.3 covers this. OK. | OK |
| E6 | Planning block heredoc contains a bare `$` that gets interpolated when the heredoc closing tag is **unquoted** | Existing heredocs use `<<'METHODOLOGY_EOF'` (quoted), preventing parameter expansion inside. Plan keeps quoted heredoc and uses sed to substitute. OK. | OK |
| E7 | Planning block contains `__SPEC_PATH__` followed by additional underscores (path collision) | Existing pattern uses double-underscore-flanked tokens; plan adds three more (`__RETRY_BUDGET__`, `__RETRY_BACKOFF__`, `__EVENT_PATH_DISPLAY__`). If a spec path contains `__RETRY_BUDGET__` literally, it would be substituted. Wildly unlikely. **LOW**. | LOW |
| E8 | Operator runs `acorn _internal halt` directly with malformed args | `[ "$#" -ge 7 ]` check exists in `cmd_internal`. OK. | OK |
| E9 | Stage 0 partial success on first attempt: 2/3 files OK, 1 failed; on retry, ALL THREE files re-touched (because operator pushed prompt rewrites) | The orchestrator's protocol is "relaunch ONLY that one agent (do NOT re-run agents whose files passed)". If the orchestrator obeys, OK. If not, only the failing file is the gate's concern — re-running passing agents is wasted effort but not incorrect. Plan §3.4.2 explicit instruction. OK. | OK |
| E10 | The retry sleep (`sleep 30`) blocks the orchestrator's tmux session for 30s | Existing watchdog `${FOREMAN_HOME}/bin/completion-watchdog.sh` may flag the session as "stalled" because no file mtime changes during sleep. Plan does not consider interaction with watchdog. **MEDIUM**. Recommendation: on a planned sleep, write a sentinel file (`.specs/<slug>/.retry-pending`) to bump mtime, or document acceptable false-positive. | MEDIUM |
| E11 | A subagent succeeds in writing the file, but only writes a partial chunk before the Task agent times out | `[ -s "$file" ]` passes (non-empty). `grep -E -q '^## ' "$file"` may pass if any header is present. The file is corrupt but validation reports OK. Pipeline advances. **MEDIUM** — explicit AC #1 says "non-empty" only, so plan is technically compliant. But this is the failure mode that motivated the issue (Wave 1 #125 had stale recon that propagated through Stage 0 silently). Header-present check is a heuristic. | MEDIUM (plan complies with AC; deeper content validation is out of scope) |
| E12 | `ACORN_FAILURE_EVENT_PATH` symlinked to a path the operator does not own | `>>` follows symlinks; if target is unwritable, append fails. Best-effort. OK. | OK |
| E13 | The orchestrator, on retry, accidentally launches a DIFFERENT agent (e.g., relaunches Agent A when only Agent C failed) | Validation passes for the actually-needed file (Agent A's), but Agent C's still fails. Retry budget is consumed against Agent A's lineage but Agent C never re-runs. **HIGH risk** if orchestrator misidentifies failed agents. Plan §3.4.2 maps relpath → agent name, so as long as the orchestrator parses stderr correctly, this won't happen. Tested by §6.6 which confirms the mapping text exists in PROMPT.md. | LOW (mitigated by explicit prompt text) |
| E14 | The bash script exit `set -e` interacts with the new helpers' `return 1` | All five new helpers return non-zero only when intentional (validate_stage_artifacts on failure, halt_pipeline_diagnostic always 1). When called from `cmd_internal`, the script exits with that code naturally. Tested by §6.5 expectations. OK. | OK |
| E15 | `ACORN_FAILURE_EVENT_PATH` shared between forge and another consumer | JSONL appends are interleaved but each line is still complete. OK. | OK |
| E16 | Empty pipeline mode passed to `stage_manifest` (`stage_manifest "" 0`) | Plan §3.2 `stage_manifest` falls through to `*) die "Unknown stage manifest..."`. Caller (`cmd_internal validate-stage`) requires 3 args but does not validate mode. If user runs `acorn _internal validate-stage /path "" 0`, `stage_manifest` will die. Acceptable — the underlying contract (planning_block_* hard-codes mode) prevents this in the orchestrator path. **LOW**. | LOW |
| E17 | `cmd_doctor` invoked when no specs exist (no `$PROJECTS_DIR/*/main/.specs`) | Existing behaviour: `printf 'No active Acorn sessions found.\n'; exit 1`. The plan's halt detection lives inside the per-spec loop, so empty-loop case is unaffected. OK. | OK |
| E18 | A halted spec is `acorn approve`-d before HALT.md is removed | `cmd_approve` (line 2403) only checks SPEC.md presence — does NOT check for HALT.md. If a spec's pipeline halted at Stage 0, no SPEC.md is produced, so approve fails with "Missing final plan". OK — appropriate failure surface. But: if a spec halted AFTER SPEC.md was already written (e.g., a hypothetical post-final-spec gate), the approve would succeed despite the halt. **LOW** — currently no post-SPEC.md stages exist; future-proofing only. | LOW |
| E19 | An old spec (created before the change) lacks the new gate text in PROMPT.md, but its `acorn doctor` invocation now scans for HALT.md | Halt scan returns no HALT.md (because old specs don't write it), so no false positive. OK. | OK |
| E20 | Spec dir contains both `recon/HALT.md` AND `plans/HALT.md` | Plan §3.5 sets halt_file to plans/HALT.md preferentially. This loses the recon halt info if both exist. **LOW** — should cite both files in the doctor output. | LOW |

### 4.2 Error paths NOT covered

| # | Error path | Plan handling |
|---|---|---|
| ER1 | `jq` parsing error in `emit_failure_event` (e.g., invalid argjson) | Plan §3.2 wraps with `2>/dev/null)" \|\| return 0`. OK |
| ER2 | `halt_pipeline_diagnostic` invoked with `agent` arg containing a newline (orchestrator passes raw text) | The newline ends up in HALT.md and as a sed-substituted token. Heredoc `printf 'Failed agent: %s\n'` handles newlines fine. JSONL `--arg agent` is jq-escaped. OK |
| ER3 | Network-equivalent failure: orchestrator's Task tool times out and returns no message | The Task return is empty. Validation runs and reports MISSING. Retry triggered. After exhaustion, halt with "(no output captured)". OK — gracefully degrades |
| ER4 | `cmd_internal` is invoked with PATH not including the script's own location | `acorn _internal halt …` calls `halt_pipeline_diagnostic` (in-process function), not a recursive `acorn` invocation. OK |
| ER5 | A retry budget overrun: orchestrator misinterprets and runs >budget retries | Bash helpers don't enforce a hard budget; the LLM is the gatekeeper. Plan §R1 acknowledges this risk. OK — accepted limitation |
| ER6 | Sub-agent crashes mid-write, leaving a partial file with valid header | Discussed in E11. Validation passes. Pipeline advances with partial recon. AC #1 only mandates "non-empty"; plan §AC mapping says this is by design. Documented as deferred (R5). OK |
| ER7 | `acorn _internal validate-stage` invoked while a Task agent is still writing | Race condition: file may be size 0 momentarily. Plan does not discuss. **MEDIUM**. Recommendation: orchestrator should wait for Task return before running validate-stage. The plan's prompt text says "After all 3 complete" which implies waiting. Tested only at the prompt-text level (§6.6). |
| ER8 | The auto-trigger message fires before Claude is ready, validate-stage gets a stale spec | The existing `wait_for_claude_ready` (line 1848) handles this for the initial trigger. Plan does not introduce new auto-trigger paths. OK |
| ER9 | Operator deletes `recon/HALT.md` manually, then runs `acorn doctor` | Plan §3.5 only checks file existence. After manual deletion, doctor reports no halt. OK — fits the "operator triage" model |
| ER10 | `validate_prompt_md` placeholder lint (R7) finds an unsubstituted `__RETRY_BUDGET__` in a spec PROMPT.md that came from a different acorn version | The render-time check refuses to write the PROMPT.md, atomic move fails, `cmd_create` dies. OK — fail-loud as intended |

### 4.3 Internal contradictions

| # | Contradiction | Severity |
|---|---|---|
| C1 | §1.3 says "Bash provides deterministic primitives; orchestrator drives control flow." But §3.5 (cmd_doctor halt detection) is bash-driven AFTER the fact. This is fine — it's "post-hoc detection", not "control flow during pipeline". Spec should clarify the two layers (in-pipeline = orchestrator, post-pipeline = bash) more explicitly. | LOW |
| C2 | §3.4.2 retry text says "Wait __RETRY_BACKOFF__ seconds (use the Bash tool: `sleep __RETRY_BACKOFF__`)". E10 above: a 30s sleep may trigger watchdog stall detection. Plan §1.3 dismisses bash-layer polling because of "fire-and-forget semantics that Foreman, watchdogs, and humans rely on". Now the watchdog flags every retry as stall. Internal tension. | MEDIUM |
| C3 | §6 testing strategy line "All tests live in `test/test_recon_completeness.sh`" but §6.12 says existing `test_doctor.sh` should be "extended with halt-detection assertions". So tests are split across two files. Plan should be explicit. | LOW |
| C4 | §6.10 e2e test uses `bash` semantics (`<<<`, `$(<file)`) but tests sourced via the existing harness pattern do not always have these niceties. `$(<file)` is a bashism, OK. `<<< "$manifest"` herestring is bashism, OK. Spec must declare bash 4+ requirement (already implied by recon §"Dependency Management"). | LOW |
| C5 | Plan §2.4 JSONL schema includes `"event":"subagent.halt"` (a single fixed event type). PROMPT.md AC #4 doesn't mandate the event name. Forge consumers may depend on this string. **LOW** — but pin it in spec. | LOW |
| C6 | §3.4.2 says orchestrator runs `acorn _internal halt …`, but §3.2 `halt_pipeline_diagnostic` always exits 1. After the Bash tool returns rc=1, the orchestrator may interpret this as "the halt command itself failed" rather than "the halt was successfully recorded". Plan §3.4.2 says "halt … exits non-zero. After running halt, STOP." — clear if read carefully, but easy to misinterpret. | MEDIUM |
| C7 | Plan §5.5 says "ACORN_FAILURE_EVENT_PATH=\"\" — events are not emitted." But §3.2 also gates on `command -v jq` — if jq is somehow missing despite being a `require_cmds` dep elsewhere, events silently disappear even when path is set. Acceptable best-effort, but contradicts "events are not emitted" only when path is empty. | LOW |

### 4.4 Security concerns

| # | Concern | Severity |
|---|---|---|
| S1 | Sed injection via `${spec_path}` (existing) and the new `${retry_budget}`, `${retry_backoff}`, `${event_path_display}` substitutions. If any of these contain `|` or `\` or other sed metacharacters, the substitution corrupts the rendered PROMPT.md. The values come from env vars or paths controlled by the operator. **LOW** in normal operation; **MEDIUM** if these values come from untrusted sources (e.g., a malicious GitHub issue with crafted slug). The slug derives from the issue title via `slugify_title` which limits to `[a-z0-9-]`, so slug-derived spec paths are safe. Env var values come from operator shell — same trust as everything else. OK |
| S2 | HALT.md path constructed as `<spec_dir>/<recon\|plans>/HALT.md`. If `spec_dir` is operator-controlled (via PROJECTS_DIR), and the operator passes a path like `/etc/`, HALT.md would be written outside the spec root. But `cmd_internal halt` accepts `spec_dir` as a positional arg with no validation. **MEDIUM** — recommend `safe_repo_main`-style validation in `cmd_internal halt` to ensure `spec_dir` is under `$PROJECTS_DIR/*/main/.specs/`. Otherwise an orchestrator hallucination could write HALT.md anywhere | MEDIUM |
| S3 | `agent_log_tail` arg is embedded inside ``` ``` fences in HALT.md. If it contains ``` the markdown breaks but no security impact. If it contains shell metachars like `$(rm -rf /)`, those are inside a heredoc-printf, not eval'd. Safe. | OK |
| S4 | `emit_failure_event` payload is jq-constructed with `--arg`/`--argjson` — these are correctly escaped by jq. No JSON injection. OK | OK |
| S5 | Concurrent writes to JSONL on the same path. POSIX guarantees `O_APPEND` write atomicity within `PIPE_BUF` (4096 bytes). Each event is ~1KB. Safe. OK | OK |
| S6 | The `_internal` subcommand is undocumented but reachable. An operator could invoke `acorn _internal halt` against any spec dir on the system, polluting it with HALT.md. **LOW** — operator-controlled access. Consider adding `acorn _internal` to the help text for transparency, OR add a check that the caller is the orchestrator (impossible in bash without ENV-based heuristics). Accept the risk. | LOW |
| S7 | The PROMPT.md content (with new gate text) is written by `cmd_create` as the operator. If operator is compromised, attacker has many easier vectors. OK | OK |

---

## 5. Recommendations Summary

The plan is generally sound and well-structured. To unblock implementation cleanly, address these in priority order in the final SPEC.md:

### Must-fix before SPEC.md (CRITICAL/HIGH)

1. **F1 (CRITICAL)**: Change `redteam_N.md` to `red_team_N.md` in stage_manifest for `full:4`. Verified codebase uses underscored filenames at lines 983-1079 of bin/acorn.
2. **F2/§3.6 (HIGH)**: Specify `[HALTED]` prefix application in BOTH `status_for_spec` return paths (label-found and fallback). Add explicit test for both.
3. **F3 (HIGH)**: Initialize `DOCTOR_FAIL=0` at top of `cmd_doctor` to fix latent `set -u` bug. Acknowledge as a drive-by fix.
4. **§3.1/§3.4.2 (HIGH)**: Provide all 11 stage gate texts verbatim in spec, with explicit agent-name mappings for each multi-agent stage (Stage 0 / Stage 1 full / Stage 4 full).
5. **§3.4 (HIGH)**: Add `__MODE__` placeholder substitution so each rendered planning block hard-codes its mode in the validate-stage / halt commands. Don't rely on the orchestrator to fill in `<MODE>`.
6. **§3.11 (HIGH)**: Move `cmd_doctor` halt detection BEFORE the `[ "$state" = "running" ] || continue` check (line 3458), or use an independent halt scan loop, so halts in dead sessions are still reported.
7. **§7.1 (HIGH)**: Reorder implementation steps so `validate_prompt_md` placeholder lint (R7) is added LAST (after Step 5), preventing self-failures during phased rollout.
8. **§3.8 (MEDIUM→HIGH for parallel-stage retries)**: Update `validate_stage_artifacts` to accumulate ALL failures, not exit on first. Lets orchestrator relaunch all failed agents in a single Task batch for parallel stages.

### Should-fix (MEDIUM)

9. **F6**: Document `--no-auto` mode interaction with Bash tool prompts. Mention in spec; no code change.
10. **F9/§3.10**: Clarify "verbatim" prompt for relaunched agents. Recommend named anchor or in-text reference.
11. **§3.7 / Risk on input validation**: Sanitize `ACORN_SUBAGENT_RETRY_BUDGET` and `ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS` to be digits-only in `planning_block_*`.
12. **§4.1 E1**: When HALT.md write fails (read-only FS), spec should emit full diagnostic to stderr.
13. **§4.1 E10 / C2**: Document watchdog interaction during 30s retry sleep. Consider sentinel file.
14. **§4.4 S2**: Add `safe_repo_main`-style validation to `cmd_internal halt`'s `spec_dir` arg.
15. **§4.3 C6**: Reword the prompt text describing `acorn _internal halt`'s exit code so the orchestrator unambiguously interprets rc=1 as "halt recorded successfully" not "halt command failed".
16. **§3.12 / E11**: Spec must explicitly note that header-presence check is a heuristic — partial-write success is possible. Defer content-quality validation as future work (already mentioned in R5).
17. **§3.5 / ER7**: Spec should explicitly state ordering: orchestrator MUST wait for all parallel Task agents to return before running validate-stage.

### Nice-to-have (LOW)

18. **F4**: Note "insert before `*)` catch-all" for `_internal` case.
19. **F5/§3.2 sed multi-line**: Pick a sed style and stick with it.
20. **§3.9 agent_log_tail**: Sanitize triple-backticks or use `~~~` fence.
21. **§4.1 E20**: When both HALT.md files exist, cite both in doctor output.
22. **§7 docs**: README.md/CLAUDE.md updates listed in §7.5 — these were not labelled as required for AC, but they make the env vars discoverable. OK to ship.

### Testing gaps that final spec must address

- AC #6 ("induce a Stage 0 sub-agent crash") — current §6.10 test is synthetic. Spec must either (a) reword AC #6 to match what's actually testable, (b) add a manual smoke test step, or (c) accept the synthetic test and document the limitation.
- No test for forge-side JSONL consumer compatibility (R8). Spec should add a smoke "forge can ingest a `subagent.halt` event without crash" check, or defer to forge's own test suite (separate repo).
- No test for `--no-auto` interaction (F6).
- No test for placeholder lint in `validate_prompt_md` (R7).

---

## 6. Validator's Overall Assessment

**Decision**: PROCEED to Stage 3 (final-spec) with the corrections above incorporated.

**Confidence**: Medium-High. The plan correctly identifies the architectural constraint (LLM-driven pipeline, bash exits early) and chooses a reasonable split between prompt-level control flow and bash-level helpers. The new function names and placement are consistent with existing acorn idioms.

**Top 3 risks remaining after corrections**:

1. **R-1 from plan**: The orchestrator LLM may not reliably follow the new gate instructions. No bash-level enforcement is possible. Mitigation: explicit, capitalised, monospaced commands; rely on `--dangerously-skip-permissions` for the Bash tool calls; manual smoke test in first ~10 runs (already in plan §R1).
2. **F1 (red_team_N.md naming)**: If not corrected, full-mode pipelines will halt on every Stage 4 → 5 transition. Easy fix; this validation surfaces it.
3. **§4.1 E11 / R5**: Header-only validation does not catch hallucinated/partial recon content. Out of scope per AC #1, but the issue's motivating Wave 1 #125 incident may not be fully prevented. Spec should call this out.

Plan is ready for Stage 3 with the prioritized corrections applied.


