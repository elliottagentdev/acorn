# Validation Report — Three-Artifact Pipeline Output Plan

**Plan under review:** `/home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/plans/draft.md`
**Validator:** Stage 2 (Lite Pipeline) — Combined Validator
**Date:** 2026-05-02

---

## Executive Summary

The draft is **structurally sound and largely accurate**. It correctly identifies the single file that needs editing (`bin/acorn`), the right injection points, and the right env-var/meta-json plumbing. The core architectural decision (one `three_artifact_instructions()` helper + three placeholder injections + soft warnings in `cmd_approve`/`cmd_spec_complete`) satisfies all eight acceptance criteria.

**However, the plan has one critical defect** (an awk-based substitution that will silently corrupt the injected block when it encounters backslashes in the markdown content) and **several significant gaps** that would block clean implementation:

1. **CRITICAL — `awk gsub` interprets backslash escapes in the replacement string.** The plan's `awk -v block="$three_block" '{gsub(/__THREE_ARTIFACT_BLOCK__/, block)} 1'` will mangle any `\<char>` sequence in the block (e.g., `\b`, `\n`, `\t`, `\&`). The block as drafted contains markdown like `\` line continuations and the YAML schema includes `verify` strings that may have backslashes. **Verified empirically** — tested with input containing `\backslash`, the `\b` was consumed and output was `ackslash`.
2. **Schema contradiction** — Plan §3.1.2's `three_artifact_instructions()` heredoc uses `THREE_ARTIFACT_EOF` quoted, which prevents variable expansion, but the comment in §3.1.4 implies the block is computed once via `$(three_artifact_instructions)` and substituted. Order is correct, but the awk substitution choice is unsafe (see #1).
3. **Pi Model Recommendation contradiction** — Plan §3.1.4 says inject the placeholder **between** "ZERO questions" and "Write the final spec to ..." line, but the existing prompt has the Pi Model Recommendation block (item 6 in the numbered list) sitting BETWEEN those two lines. Plan would split the existing list. Inspect lines 1100-1118 of `bin/acorn`: the "ZERO questions" line is at 1116, then blank, then "- Write the final spec to ..." at 1118. **Not split** — the Pi Model Rec is item #6 ABOVE the "ZERO questions" line. Plan is correct on this point. (Re-verified — see Fact-Check §F4.)
4. **Test bug** — Tests 1 and 2 (`test_default_output_mode_is_single`, `test_unknown_output_mode_falls_back_to_single`) re-source the script via `eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"`. But the script's top-level `set -euo pipefail` and PATH manipulation will execute every time. More importantly, the validation case statement in §3.1.1 runs at script-source time and may emit `[WARN]` to stderr — the test file would emit those warnings as side effects. Tests should mock or capture them.
5. **`set -u` interaction with `${ACORN_OUTPUT_MODE:-single}` in tests** — When `unset ACORN_OUTPUT_MODE` precedes an `eval`, the case statement `case "$ACORN_OUTPUT_MODE" in` will trigger an unbound-variable error under `set -u`. The plan's §3.1.1 sets `ACORN_OUTPUT_MODE="${ACORN_OUTPUT_MODE:-single}"` BEFORE the case statement, so this is fine in production — but it shows the assignment must come first. The plan has the right ordering; just flagging the brittleness.
6. **Missing AC #7 verification path** — Plan §7.3 says manual smoke test is "not scripted", but AC #7 explicitly requires running `acorn create <repo> <issue> --lite` and verifying all three files. There is no automated check that an end-to-end three-artifact run actually produces three files. This is a gap (acknowledged but not closed).
7. **Forge-coupling check missing** — Constraint says "Forge-specific assumptions live in Foreman dispatch wrappers, not in the Acorn binary." Plan touches `claude/commands/acorn.md` (acorn doc) but doesn't audit that the new prompts are forge-agnostic. Verified by reading the proposed `three_artifact_instructions()`: ✅ no `forge`, `foreman`, or `pi` references. **Pass.**
8. **Documentation update target wrong** — Plan §3.3 says "update `claude/commands/acorn.md` lines ~211-223". Actual layout block is at lines 204-223 (verified). Off by ~7 lines but content shape matches.

The remainder of this report documents all four required dimensions: requirements coverage, fact-check, ambiguity audit, and edge cases & risks.

---

## 1. Requirements Coverage Matrix

For each acceptance criterion in PROMPT.md:

| AC # | Requirement (paraphrased) | Addressed in plan? | Where | Testable? | Gaps |
|---|---|---|---|---|---|
| 1 | Configurable mode via env var `ACORN_OUTPUT_MODE` with `single` (default) and `three-artifact` | ✅ Yes | §3.1.1 (constants), §3.1.6 (cmd_create reads it), §5.3 (env var contract), tests 1-2 | ✅ Yes (tests 1, 2, 7, 8) | None — but no CLI flag; PROMPT.md says "or equivalent CLI flag" — env var alone is acceptable per AC text. ✅ |
| 2 | Stage-level emission in all three pipeline modes (quick / lite / full) | ✅ Yes | §3.1.4 (apply to all three planning_block_* functions), tests 3-6 | ✅ Yes (tests 4, 5, 6) | Plan says inject `__THREE_ARTIFACT_BLOCK__` placeholder once per heredoc — but doesn't show the EXACT modified heredoc text for full and quick modes. Lite is shown; full and quick are "same edit, applied". This is a significant gap because the existing heredocs have different structures (full has 5 stages, quick has 1 direct-spec stage). |
| 3 | PLAN.md schema with 5 required sections in order | ✅ Yes | §3.1.2 (heredoc text), §4.2 | ⚠️ Partial — schema is enforced via prompt only. No bash-side validation. AC #8 forbids new deps so this is acceptable. Test 4 asserts strings present in prompt. | None |
| 4 | TASKS.md schema (YAML blocks with id/title/size/files/verify/depends_on; XL flag) | ✅ Yes | §3.1.2 (heredoc text), §4.3 | ⚠️ Partial — same as #3. Test 4 asserts schema strings present. | The XL note uses an emoji `⚠️` which may not render correctly through the heredoc → awk → sed pipeline (see Fact-Check §F2 — UTF-8 char survives `awk -v` but verify before merge). |
| 5 | SPEC.md backwards-compat in three-artifact mode (trim §3 + §7, remain stand-alone) | ✅ Yes | §3.1.2 ("KEEP" / "REMOVE" lists in heredoc) | ⚠️ Partial — relies on LLM following prompt; no bash-side check. Test 4 asserts "TRIMMED" and "valid stand-alone" strings present in prompt. | The plan's KEEP/REMOVE lists reference "## 1.", "## 2.", etc. but these section numbers are NOT what the existing Stage 5/Stage 3/Stage 1 prompts produce — the existing prompt template asks for "Requirements Traceability Matrix", "Validation Resolution Log", etc. without section numbers (see lines 1083-1116). The plan's section numbers don't map to anything specified — they're invented. **GAP: Either remove the section numbers, or update the prompt to match.** |
| 6 | `acorn approve` and `acorn spec-complete` warn (not error) on missing PLAN.md / TASKS.md | ✅ Yes | §3.1.8, §3.1.9, tests 9-10 | ✅ Yes | None |
| 7 | Test: real `acorn create --lite` against representative issue produces all three files; SPEC.md valid stand-alone | ⚠️ Partial | §7.3 (manual smoke test only) | ❌ NO — manual procedure, not automated | **GAP**: AC #7 says "Test: run …" — implying automated. Plan defers to manual smoke test. Acceptable for v1 but should be flagged. |
| 8 | No new dependencies (bash/jq/awk only) | ✅ Yes | §2.1, §10 (R3), §6.6 (defers TASKS.md parsing) | ✅ Yes (visual inspection) | Plan introduces `awk` use (already a coreutil, no new dep). ✅ |

**Coverage summary: 8/8 ACs addressed. 2 with significant gaps (AC #2 incomplete demo for full/quick; AC #5 invented section numbers). 1 deferred to manual procedure (AC #7).**

---

## 2. Codebase Fact-Check

Each numbered claim from the plan is checked against `/home/agentdev/projects/acorn/main/bin/acorn` (3690 lines verified via `wc -l`).

### F1. File line counts (mostly accurate, off-by-a-few)

| Plan claim | Actual | Status |
|---|---|---|
| `bin/acorn` is "~3700 lines" | 3690 | ✅ Accurate |
| `planning_block()` at line 662 | line 662 | ✅ Exact |
| `planning_block_full()` at line 673 | line 673 | ✅ Exact |
| `planning_block_lite()` at line 1141 | line 1141 | ✅ Exact |
| `planning_block_quick()` at line 1419 | line 1419 | ✅ Exact |
| `render_prompt_md()` at line 1621 | line 1621 | ✅ Exact |
| `write_meta_json()` at line 1948 | line 1948 | ✅ Exact |
| `cmd_create()` at line 2209 | line 2209 | ✅ Exact |
| `cmd_approve()` at line 2392 | line 2392 | ✅ Exact |
| `cmd_spec_complete()` at line 2434 | line 2434 | ✅ Exact |
| Final Spec prompt in `planning_block_lite` "approximately lines 1350-1399" | Stage 3 Final Spec prompt body 1350-1400 | ✅ Accurate |
| Final Spec prompt in `planning_block_full` "approximately lines 1074-1122" | Stage 5 prompt body 1074-1122 | ✅ Accurate |
| Direct Spec prompt in `planning_block_quick` "approximately lines 1540-1590" | Stage 1 Direct Spec body 1542-1590 | ✅ Accurate |
| `cmd_approve` SPEC.md guard at line 2403 | line 2403 | ✅ Exact |
| `cmd_spec_complete` SPEC.md guard at line 2445 | line 2445 | ✅ Exact |

### F2. Heredoc / sed mechanism (CRITICAL FINDING)

**Plan claim (§6.5):** "Use `awk -v block="$three_block" '{gsub(/__THREE_ARTIFACT_BLOCK__/, block)} 1'` instead of sed. … `awk -v` handles multi-line variable substitution safely; sed would require escaping every special character in the block."

**Empirical test:**
```bash
$ printf '__THREE_ARTIFACT_BLOCK__\n' | awk -v block="line1
line2 with /slash and \\backslash
line3" '{gsub(/__THREE_ARTIFACT_BLOCK__/, block)} 1'
line1
line2 with /slash and ackslash    <-- \b CONSUMED
line3
```

**Issue:** `awk gsub`'s replacement string interprets `\\` as `\`, `\&` as literal `&`, and `\<digit>` as backreferences. More dangerously, in `awk -v block=...`, the shell's quoting rules mean a literal backslash inside the variable is also subject to awk's escape interpretation when used as the second arg to `gsub`.

**The block as drafted in §3.1.2 contains:**
- Backticks (`` ` ``) — safe
- Forward slashes (`/`) — safe
- Markdown bullets (`-`) — safe
- YAML `:`, `[`, `]`, `#` — safe
- The `⚠️` emoji (4-byte UTF-8) — **must verify** survives awk processing on the platform (test on Linux x86_64)
- No backslashes in current draft text — **but**: if a future schema adds e.g. `verify: "grep -E '^\d+'"` example, the `\d` would silently become `d`.

**Mitigation options (rank-ordered):**
1. **Prefer:** Use a Python/Perl one-liner if available — but AC #8 forbids new deps.
2. **Recommended:** Write the block to a temporary file and use `awk` with `getline` from that file (awk treats file content as literal). Pattern:
   ```bash
   local block_tmp; block_tmp="$(mktemp)"
   three_artifact_instructions > "$block_tmp"
   awk -v block_file="$block_tmp" '
     /__THREE_ARTIFACT_BLOCK__/ {
       while ((getline line < block_file) > 0) print line
       close(block_file)
       next
     }
     { print }
   ' <<<"$heredoc_text"
   rm -f "$block_tmp"
   ```
3. **Alternative:** Use a sentinel-line approach with sed and `r` (read file): `sed '/__THREE_ARTIFACT_BLOCK__/r block_file' | sed '/__THREE_ARTIFACT_BLOCK__/d'`
4. **Last resort:** Pre-escape the block: `block="${block//\\/\\\\}"; block="${block//&/\\&}"` before passing to awk. Brittle.

**This must be fixed in the final spec.**

**Plan claim (§6.5):** "Order matters: awk substitution MUST run BEFORE the sed `__SPEC_PATH__` substitution. … 1. awk injects `three_block` (which contains `__SPEC_PATH__` literals) into the heredoc, replacing `__THREE_ARTIFACT_BLOCK__`. 2. sed then replaces all `__SPEC_PATH__` tokens (both from the original heredoc and from the freshly-injected three-artifact block)."

✅ **Order analysis correct.** The pipe ordering shown in §3.1.4 (`cat <<EOF | awk ... | sed "s|__SPEC_PATH__|...|g"`) is right.

### F3. Existing function signatures (verified)

| Plan claim | Actual signature | Status |
|---|---|---|
| `planning_block(mode, spec_path)` | `local mode="${1:-full}"; local spec_path="${2:-.}"` (lines 663-664) | ✅ |
| `planning_block_full(spec_path)` | `local spec_path="${1:-.}"` (line 674) | ✅ |
| `planning_block_lite(spec_path)` | `local spec_path="${1:-.}"` (line 1142) | ✅ |
| `planning_block_quick(spec_path)` | `local spec_path="${1:-.}"` (line 1420) | ✅ |
| `render_prompt_md(...7 args)` | 7 positional args matching plan (lines 1622-1628) | ✅ |
| `write_meta_json(...8 args, last is mode)` | 8 positional args, `mode="${8:-full}"` (lines 1949-1956) | ✅ |
| `cmd_approve` requires SPEC.md via `die` | `[ -f "$dir/plans/SPEC.md" ] || die "Missing final plan: $dir/plans/SPEC.md"` (line 2403) | ✅ Exact text match |
| `cmd_spec_complete` requires SPEC.md via `die` | Same text at line 2445 | ✅ |

### F4. Pi Model Recommendation block placement

**Plan claim:** placeholder `__THREE_ARTIFACT_BLOCK__` goes between "ZERO questions" line and "Write the final spec to" line.

**Verification (lines 1116-1118 of `bin/acorn`, full mode):**
```
The spec must be ready to be handed to a developer or agent for implementation with ZERO questions.   <-- line 1116

- Write the final spec to __SPEC_PATH__/plans/SPEC.md                                                  <-- line 1118
```

✅ **The Pi Model Recommendation is item #6 in the numbered list ABOVE the "ZERO questions" line, not between them.** Plan placement is correct. (My executive summary item #3 incorrectly flagged this; correcting here.)

However, **a separate concern**: the plan's `three_artifact_instructions()` text contains markdown headers (`### THREE-ARTIFACT OUTPUT MODE`, `#### 1. __SPEC_PATH__/plans/SPEC.md`). When injected between "ZERO questions" and "Write the final spec…", these headers will appear AFTER the numbered list (1-6) of spec sections in the agent prompt, but the heredoc's prose still says "It MUST include: 1. … 2. … 3. … 4. … 5. … 6. Pi Model Recommendation … The spec must be ready to be handed …". The injected three-artifact block will sit at the end and include re-instructions about file paths. **No structural conflict, but the prompt becomes less coherent** — the LLM reads "include sections 1-6" then sees "actually emit three files" later. Recommend the prompt be restructured so that in three-artifact mode, the original Stage-5/3/1 prompt instructions are SUPERSEDED rather than supplemented.

### F5. `cmd_create` arg parsing

**Plan claim §3.1.6:** "Add after the existing arg-parse loop (~line 2235), and before the render_prompt_md call (~line 2276)".

**Verification:**
- Arg-parse loop ends at line 2234.
- `render_prompt_md` call at line 2276.
- Insertion window 2235-2275 is correct.

✅ Accurate.

### F6. `auto_trigger_message()` — does it need updating?

**Plan claim (§5 Architecture, also §3.1.10 implicit):** Plan does NOT propose changing `auto_trigger_message()` (lines 25-33). Recon notes "may need no change since the PROMPT.md already encodes the mode behavior".

**Verification:** The auto-trigger only references "execute the lite/quick/full N-stage planning pipeline" and "write all output files to %s/". Since the methodology is in PROMPT.md and three-artifact is just additional file emission within the existing methodology, **no change required**. ✅

**However:** The auto-trigger says "Write all output files to %s/" — if the LLM in three-artifact mode writes only SPEC.md and forgets PLAN/TASKS, this auto-trigger doesn't enforce anything. Acceptable per plan §6.2 (LLM hallucination is detected later).

### F7. Tests sourcing pattern

**Plan claim:** Tests use `eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"`.

**Verification (test/test_split.sh line 8):** `eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"` — exact match.

✅ Pattern correct. **But note:** sourcing the script will execute the new validation case statement at top of `bin/acorn`, which can emit a `[WARN]` to stderr if `ACORN_OUTPUT_MODE` is set to an invalid value in the test shell's env. Tests must `unset ACORN_OUTPUT_MODE` before sourcing OR explicitly set it to `single` to avoid noise.

### F8. `claude/commands/acorn.md` documentation update

**Plan claim §3.3:** "Update the 'Spec directory layout' table (lines ~211-223)".

**Verification:** The directory layout block in `claude/commands/acorn.md` is at lines 204-223 (header at 202, code fence at 205, content 206-222, fence close 223). The plan's line range is off by ~7 but the target content is unambiguous.

✅ Acceptable — line numbers will likely drift before implementation anyway.

### F9. `meta.json` schema migration safety

**Plan claim §4.1, §6.4:** Existing meta.json files lack `output_mode` field; readers use `jq -r '.output_mode // "single"'` defaulting.

**Verification:** Pattern `jq -r '.foo // "default"'` is jq-standard and works correctly on missing fields and on null. Verified safe. ✅

### F10. `cmd_approve` Forge integration

**Plan claim:** Doesn't break Forge's `spec-metadata-extract.sh` integration.

**Verification (lines 2416-2431 of `bin/acorn`):**
```bash
local foreman_home="${FOREMAN_HOME:-$HOME/.foreman}"
local extract_script="${foreman_home}/bin/spec-metadata-extract.sh"
if [ -x "$extract_script" ]; then
  ...
  meta_json="$(bash "$extract_script" "$dir" 2>/dev/null)" || meta_json=""
  ...
fi
```

The extract script is invoked with `"$dir"` (the spec directory). It writes to `metadata.json`. The plan's new `output_mode` field in `meta.json` (different file) does not affect this path. **However**, if `spec-metadata-extract.sh` reads from `meta.json` to determine schema (we don't have visibility into that script), adding `output_mode` is forward-compatible (jq ignores unknown fields by default).

⚠️ **Recommend:** Final spec should add a note saying "verify `spec-metadata-extract.sh` does not strict-validate `meta.json` schema before merge".

### F11. Existing test for `cmd_approve` / `cmd_spec_complete`?

**Search result:** `grep -l 'cmd_approve\|cmd_spec_complete' test/*.sh` finds **no existing test file** that tests these functions directly. `test/test_labels.sh` tests label functions but not cmd_approve. So plan's test 9 and test 10 are the FIRST tests for `cmd_approve`. **This is a useful improvement but means there's no baseline to regression-test against.** Recommend adding a "single-mode happy path" test for cmd_approve to ensure the existing path isn't broken.

### F12. Recon doc claims about external integration

**Recon `architecture.md` claims:** "Acorn integrates with the Forged daemon (at `localhost:7700`) for: Circuit breaker check before `cmd_create` … Spec metadata extraction on `acorn approve` via `$FOREMAN_HOME/bin/spec-metadata-extract.sh`".

**Verification:** `cmd_create` calls `check_circuit_breaker` at line 2245. `cmd_approve` calls `spec-metadata-extract.sh` at line 2421. ✅ Recon facts are accurate.

### F13. Plan's mocked `spec_dir` in tests

**Plan claim (test 9, line 654 of draft.md):**
```bash
spec_dir() { printf '%s' "$dir"; }
export -f spec_dir
```

**Concern:** `spec_dir` is called inside `cmd_approve` via `dir="$(spec_dir "$repo" "$slug")"`. The mock ignores its args and returns `$dir` (a closure-captured local). When the test function exits, `$dir` goes out of scope BUT `export -f` exports the function, not the variable. The function body still references `$dir` by name — at call time, bash will look up `$dir` in the calling scope. This will work because `cmd_approve` is called from inside the same test function while `$dir` is still in scope. **OK in practice but fragile.** Recommend explicitly capturing: `local d="$dir"; spec_dir() { printf '%s' "$d"; }` or use a global env var.

### F14. Risk register R4 — "Inspected `spec-metadata-extract.sh` integration in `cmd_approve` — only writes, doesn't read field schema."

**Verification:** The plan claims to have inspected this script. The script lives in `$FOREMAN_HOME/bin/spec-metadata-extract.sh` which is OUT OF THIS REPO (Forge's repo). Acorn invokes it but doesn't bundle it. **Plan made an unverifiable claim.** The script may or may not parse `meta.json` schema. Recommend: lower confidence on R4, OR add a deferred follow-up to verify Forge-side compat before forge enables three-artifact mode in production.

### F15. `auto_trigger_message` referenced in line numbers

**Recon `relevant_code.md` claims:** `auto_trigger_message()` at lines 25-33.

**Verification:** Lines 25-33 of `bin/acorn`. ✅ Confirmed.

### F16. PROMPT.md acceptance-criteria text exact-match

The plan's `three_artifact_instructions()` heredoc contains schemas. Comparing to PROMPT.md AC #3 and AC #4:

| PROMPT.md AC text | Plan heredoc text | Match? |
|---|---|---|
| "Architecture decisions with rationale (1-3 bullet points each; cite alternatives considered)" | "## 1. Architecture Decisions / For each decision: 1-3 bullet points with rationale; cite alternatives considered and why rejected." | ✅ Same intent, slight wording variance |
| "API contracts (inputs / outputs / side effects per touched function or interface)" | "## 2. API Contracts / For each touched function or interface: Inputs (types, validation rules) Outputs (return type, error modes) Side effects (files written, network calls, state mutations)" | ✅ Plan EXPANDS the AC with helpful detail |
| "Data model changes (schemas, migrations, atomic-rename patterns)" | "## 3. Data Model Changes / Schemas, migrations, atomic-rename patterns. If no data changes, write 'No data model changes.'" | ✅ Plan adds graceful "no changes" guidance |
| "Implementation sequence (phase names + dependencies)" | "## 4. Implementation Sequence / Phase names with dependency graph. Each phase independently verifiable." | ✅ |
| "Risk register (known unknowns)" | "## 5. Risk Register / Known unknowns: severity (low/med/high), likelihood, mitigation." | ✅ Plan adds severity scale |
| YAML schema with id/title/size/files/verify/depends_on | Identical YAML in plan | ✅ Exact |
| "XL tasks (>8 files OR >3 new interfaces) flagged with `⚠️ XL: requires decomposition` note" | "XL: >8 files OR >3 new interfaces — flag with note: ⚠️ XL: requires decomposition" | ✅ |

✅ **Schema fidelity is good.** The plan slightly enriches some sections (helpful) and the YAML is bit-exact.

---

## 3. Ambiguity Audit

For each major plan section, what's missing or open to interpretation?

### A1. §3.1.1 — Constants block placement

**Plan says:** "End of the existing global-constants block, before utility functions begin."

**Ambiguity:** The script has constants at lines 5-12, then PATH manipulation at 14-23, then `auto_trigger_message()` at 25 (a function, not a constant). So "end of constants block" could mean line 13 (before PATH) or line 24 (after PATH). The PATH block is wrapped in a `case` statement that could fail under `set -u` if `_claude_bin` is unset (it's not — `command -v` returns empty). **Resolution:** Place new constants at line 13 (immediately after `_LIST_NWO=""`) to group with other globals and run before any `case` statement that uses `set -u`-sensitive expansion.

### A2. §3.1.1 — Validation case statement re-runs on every script invocation

**Plan says:** Add a case statement after the env-var declaration that warns + falls back if the value is invalid.

**Ambiguity:** This case statement runs **every time `acorn` is invoked**, including for unrelated commands like `acorn list` or `acorn doctor`. If a user has `ACORN_OUTPUT_MODE=triple` in their shell rc forever, every command emits a warning. **Resolution:** Either (a) only validate inside `cmd_create` where the value is actually used, or (b) accept the warning noise as a feature ("typo notification"). Plan should pick one explicitly.

### A3. §3.1.2 — `three_artifact_instructions` placement

**Plan says:** "place near `planning_block()` ~line 660".

**Ambiguity:** Before or after `planning_block()`? Before `planning_block_full`? The Bash function definition order matters for forward references. Since `three_artifact_instructions` is called from inside `planning_block_lite/full/quick`, it must be defined BEFORE those functions. Recommend placing it immediately before `planning_block()` (line 661) so it's clearly grouped.

### A4. §3.1.4 — Heredoc edit: where exactly is `__THREE_ARTIFACT_BLOCK__` placed in each mode?

**Plan shows lite mode in detail.** Quick and full are "same edit applied". But:
- **Full mode (Stage 5):** What about line 1078 ("Read ALL of: __SPEC_PATH__/plans/red_team_1.md through ...")? Does the new block come before or after the red-team reading instruction? Plan implies same position (between "ZERO questions" and "Write the final spec…").
- **Quick mode (Stage 1):** What about the "Be specific — reference actual file paths…" line at 1584? Plan doesn't address this.

**Resolution:** Final spec should explicitly show the modified heredoc snippet for ALL THREE modes, not just lite.

### A5. §3.1.6 — User-visible echo "Output mode: $output_mode"

**Plan says:** "Add a user-visible echo (after the existing 'Mode: $mode' echo)".

**Ambiguity:** Should this only print when `output_mode != "single"`? Or always? Plan says always. **Recommendation:** Always print — operators benefit from seeing both modes side-by-side, especially when debugging "why didn't I get three files?" type issues.

### A6. §3.1.7 — `write_meta_json` 9th positional arg

**Plan says:** Add `output_mode` as the 9th positional arg.

**Ambiguity:** What if a future feature wants to add a 10th arg? Positional args become unwieldy. Plan doesn't mention this concern. **Acceptable for v1**, but a future refactor to use named keys (e.g., a single JSON arg) might be wise. Flag as deferred.

### A7. §3.1.8, §3.1.9 — Reading `output_mode` from meta.json at approve/complete time

**Plan says:** "Why read from `meta.json`, not env var: `acorn approve` may run in a different shell session, hours later, without `ACORN_OUTPUT_MODE` set."

**Ambiguity:** What if `meta.json` is missing entirely? The plan handles this:
```bash
recorded_output_mode="$(jq -r '.output_mode // "single"' "$dir/meta.json" 2>/dev/null || printf 'single')"
```
The `2>/dev/null || printf 'single'` chain handles missing-file. ✅ But: what about a `meta.json` that exists but is malformed JSON? `jq` exits non-zero and prints to stderr. The `2>/dev/null` swallows stderr; the `|| printf 'single'` catches the non-zero exit. ✅ Robust.

### A8. §3.2 — Test for `cmd_approve` mocks `spec_dir`

**Plan's test 9 mocks:**
```bash
spec_dir() { printf '%s' "$dir"; }
export -f spec_dir
```

**Ambiguity:** The actual `spec_dir` function takes `repo` and `slug` args. The mock ignores them. If a future change makes `cmd_approve` call `spec_dir` with different args (e.g., for a sub-spec), the mock breaks silently. **Recommendation:** Add `assert_eq` on the call args, or use a more robust mock.

### A9. Order of phase implementation (§8)

**Plan §8 says Phase 1 → 2 → 3 → 4 → 5 → 6 → 7.**

**Ambiguity:** Phase 4 ("Approval-time warnings") depends on Phase 2 ("plumbing") for the `output_mode` field in `meta.json`. But Phase 3 ("Caller integration in cmd_create") is what actually writes the field. Without Phase 3, Phase 4's `jq -r '.output_mode // "single"'` always returns `"single"`, so the warnings never fire. **Resolution:** Phase 4 must come AFTER Phase 3, not after Phase 2. Plan currently lists 4's dependency as "Phase 2" — should be "Phase 3".

### A10. §3.3 — Documentation update places new section "between Pipeline Modes and Examples"

**Verification:** Looked at `claude/commands/acorn.md` — there are sections "Pipeline modes" (line ~190), "Project layout" (line 202), "Image handling" (225), "GitHub label lifecycle" (233), "Dependencies" (249). **There is no "Examples" section.** Plan's positional reference is wrong.

**Resolution:** Place "Output Modes" subsection after "Pipeline modes" (around line 200) or after "Project layout" (around line 224). Final spec should pick one.

### A11. SPEC.md trim — what exactly stays?

**Plan §3.1.2 lists KEEP and REMOVE sections, but uses section numbers (## 1., ## 2., etc.) that don't match the existing prompt template.**

The existing Stage 5 / Stage 3 / Stage 1 prompts produce output with sections named:
1. Requirements Traceability Matrix
2. Validation Resolution Log (lite) / Red Team Resolution Log (full) / [no log] (quick)
3. Implementation Plan
4. Testing Strategy
5. Risk Register
6. Pi Model Recommendation (placed at top, not numbered in the list)

The plan's trim instructions reference "## 3. Implementation Plan", "## 4. Architecture / Data Model", "## 5. Testing Strategy", "## 6. Risk Register", "## 7. Acceptance Criteria" — but the existing prompt template only produces sections 1-5 (or 1-6) with different content. **The plan's section numbers reference a SPEC.md template that doesn't exist.**

**Resolution:** Final spec must either (a) describe the trim by section NAME not number, OR (b) define the canonical SPEC.md layout that downstream consumers (and existing tests) expect. This is a real gap that will produce inconsistent SPEC.md outputs without resolution.

### A12. TASKS.md — what working dir for `verify` commands?

**Plan §12 question 4:** "Should verify commands assume a working dir? Default to repo root? Current plan: leave to LLM judgment."

**Ambiguity flagged by plan author.** Final spec should either:
- Specify "verify commands run from repo root" (matches existing test convention `bash test/test_x.sh`)
- Or specify "include explicit `cd` if needed"
- Or accept the ambiguity and rely on downstream Forge wrappers to canonicalize.

**Recommendation:** Add to `three_artifact_instructions()`: "Verify commands MUST be runnable from the repo root with no implicit `cd`."

### A13. TASKS.md — what about cleanup or revert tasks?

**Ambiguity:** The schema doesn't reserve a way to mark "this task supersedes T3" or "this task rolls back T7". For decomposed XL tasks, plan says "T7.a-T7.c" but the YAML schema's `id: T1` field doesn't show how to encode dot-notation IDs. Plan doesn't address task lifecycle. **Defer to future work, but flag.**

### A14. `auto_trigger_message` does NOT mention three-artifact

**Plan says no change needed.** ✅ True. But: the auto-trigger message is sent to the LLM after PROMPT.md is generated. If a user reads only the auto-trigger and ignores PROMPT.md, they'd miss three-artifact instructions. The auto-trigger says "Read %s/PROMPT.md and follow ALL instructions" — so it's covered. ✅ No change needed.

---

## 4. Edge Cases & Risks

### E1. CRITICAL: awk gsub backslash interpretation (re-emphasize)

Already covered in §F2. **Must be fixed before merge.** Use `awk getline < file` or `sed r file_name` instead of `awk -v block="$var" gsub`.

### E2. Empty `three_artifact_instructions()` output

**Scenario:** What if the function returns empty (e.g., bug)?
**Behavior:** `awk -v block=""` would substitute `__THREE_ARTIFACT_BLOCK__` with empty string. The placeholder line in the heredoc is the only content of that line, so it becomes a blank line. ✅ Safe degradation.

**Test gap:** No plan test exercises this. Add: `test_three_artifact_function_emits_nonempty()`.

### E3. Concurrent `acorn create` for same issue

**Plan §6.7:** "Pre-existing concern, not introduced by this feature."

**Verification:** True — atomic-mv pattern in `render_prompt_md` already exists. But: the new `write_meta_json` call is NOT atomic (no temp+mv). Two concurrent `acorn create` invocations could race on `meta.json` write. **Pre-existing bug**, but plan doesn't fix it. Recommend adding `mv` pattern to `write_meta_json`. Defer if out-of-scope.

### E4. `ACORN_OUTPUT_MODE` set in `acorn create` but not in approve session

**Plan handles correctly via meta.json read.** ✅ See A7.

### E5. Reverse: meta.json says `single` but operator wants three-artifact at approve time

**Scenario:** Operator created spec with default `single` mode, then later wants to convert. Sets `ACORN_OUTPUT_MODE=three-artifact` and re-runs approve.
**Behavior per plan §6.3:** "approval should reflect the spec's actual generation mode, not the operator's current session env." So approve does NOT warn. **OK.** But documentation should make this clear.
**Recovery path missing:** No way to "upgrade" a single-mode spec to three-artifact other than re-running `acorn create` (which would skip if PROMPT.md exists per line 2285-2287).

**Recommendation:** Add a documented procedure: `rm spec_dir/PROMPT.md && ACORN_OUTPUT_MODE=three-artifact acorn create ...`. Or add a `--force` flag to `acorn create`.

### E6. LLM partial output: SPEC.md written, PLAN.md half-written, TASKS.md missing

**Scenario:** Network blip, OOM mid-write.
**Plan §6.2:** Approve warns, doesn't fail.
**Gap:** If PLAN.md exists but is empty or truncated (no closing section), no validation. Plan §6.6 explicitly defers parse errors to downstream consumers.
**Risk:** Operator approves a malformed spec, downstream parser crashes hours later.
**Mitigation suggestion:** `cmd_approve` could check PLAN.md and TASKS.md are non-empty (`-s`) in addition to existing (`-f`). Plan doesn't currently do this.

### E7. `--quick` mode + three-artifact

**Plan covers this.** ✅ Quick mode's single Direct Spec agent emits all three.

**Edge case:** Quick mode is "best for straightforward features". Producing PLAN.md + TASKS.md from a quick-mode spec may be lower-quality (less validation, no draft+validate cycle). Plan doesn't flag this quality concern. **Recommendation:** Final spec should add a note: "Three-artifact output in quick mode produces less-validated PLAN.md/TASKS.md; prefer lite or full mode for production planning."

### E8. PROMPT.md regeneration edge case

**Scenario:** Spec dir already has PROMPT.md (from a previous `acorn create`); operator now sets `ACORN_OUTPUT_MODE=three-artifact` and re-runs.
**Verification (lines 2269, 2285-2287):**
```bash
if [ ! -f "$prompt_path" ]; then
  ...
  render_prompt_md ...
  ...
else
  info "PROMPT.md already exists, leaving as-is"
fi
```

**Behavior:** PROMPT.md is NOT regenerated. So the LLM sees the OLD prompt (single-mode). But `meta.json` IS regenerated (line 2331 unconditionally). So meta.json says `output_mode: three-artifact` but PROMPT.md doesn't have three-artifact instructions. **Inconsistent state.** When approval time comes, warnings fire about missing PLAN.md/TASKS.md but the LLM never had instructions to produce them.

**Recommendation:** Either:
- (a) Detect mode mismatch in `cmd_create` and refuse to proceed without `--force`.
- (b) Add explicit check: if `meta.json.output_mode` exists and differs from current env, warn loudly.
- (c) Document that `acorn create` must be invoked with consistent `ACORN_OUTPUT_MODE` for the lifetime of a spec.

Plan doesn't address this.

### E9. Heredoc line length and PROMPT.md size growth

**Calculation:** Three-artifact block adds ~80 lines to each generated PROMPT.md. PROMPT.md is read by the LLM as its master prompt. For a typical issue PROMPT.md (~3000-4000 lines including methodology), 80 extra lines is negligible (~2% increase). ✅ Plan §10 R-non-risk dismisses this; correct.

### E10. Schema drift across Acorn versions

**Plan R10:** "Downstream consumer breaks if TASKS.md format drifts."
**Mitigation suggested:** "Schema documented in `claude/commands/acorn.md`; version-tagged via git tags."
**Reality check:** No version tagging convention exists in this repo (no `VERSION` file, no `.git-version`). Forge consumers would have to git-pin Acorn or detect schema by inspection.
**Recommendation:** Add explicit schema version comment in TASKS.md output (e.g., `# acorn-tasks-schema: v1`). Trivial to add to the prompt; saves much pain later.

### E11. Security — prompt injection via issue body

**Scenario:** Malicious issue body contains text like `__THREE_ARTIFACT_BLOCK__` literally.
**Behavior:** When `render_prompt_md` runs, the issue body is rendered into PROMPT.md before `planning_block` is called. So the body could in theory contain `__THREE_ARTIFACT_BLOCK__` text. But: the awk substitution happens INSIDE `planning_block_*()`, which only operates on the heredoc OUTPUT (not the body). The body text is appended to PROMPT.md after planning_block returns. So an issue body cannot inject the placeholder. ✅ Safe.

**However:** an issue body can contain `__SPEC_PATH__` literally. The current code already has this risk (sed substitution). Body is rendered before planning_block, so body's `__SPEC_PATH__` is NOT substituted. ✅ Pre-existing safe behavior; plan doesn't change it.

### E12. Security — output_mode env var injection

**Scenario:** `ACORN_OUTPUT_MODE='single; rm -rf /'`.
**Behavior:** The value is used as a string in `case "$ACORN_OUTPUT_MODE" in single|three-artifact)`. The pattern matching is literal string comparison. The value is also written to meta.json via `--arg output_mode "$output_mode"` (jq's `--arg` is safe). ✅ No injection vector.

**However:** `cmd_create` includes `echo "Output mode: $output_mode"` which is also string-printed safely. ✅

### E13. Test 9 / 10 race on `notify_telegram`

**Plan test 9 mocks `notify_telegram` to a no-op.**
**Concern:** `cmd_approve` also calls `notify_foreman`? Let me check…

**Verification (cmd_approve, lines 2392-2432):**
- Calls `notify_telegram` at line 2414. ✅ Mocked.
- Does NOT call `notify_foreman` (that's `cmd_spec_complete`).

So test 9 is correctly mocked. Test 10 should also work for `cmd_approve`. **But the plan doesn't include a test for `cmd_spec_complete` warnings.** This is a gap — AC #6 covers BOTH approve AND spec-complete, but only approve is tested.

**Recommendation:** Add `test_spec_complete_warns_on_missing_plan_in_three_artifact_mode()` paralleling test 9.

### E14. `cmd_approve` writes metadata.json — interaction with output_mode

**Verification (lines 2416-2431):** `cmd_approve` runs `spec-metadata-extract.sh "$dir"` which presumably reads SPEC.md and writes `metadata.json` (different file from `meta.json`). The script likely doesn't know about PLAN.md/TASKS.md.
**Risk:** The extracted metadata may be incomplete in three-artifact mode (e.g., the Acceptance Criteria section is now in TASKS.md, not SPEC.md).
**Mitigation:** Per the upstreamability constraint, this is forge-owned. Plan §9.2 step 3 says "Forge's Foreman wrappers (e.g., `spec-metadata-extract.sh`) gain TASKS.md parsing logic (out of scope for this PR)." ✅ Acknowledged.

### E15. `cmd_clean` — does it remove PLAN.md/TASKS.md?

**Verification (line 2471 of `bin/acorn`):** `cmd_clean` removes the spec directory. PLAN.md and TASKS.md are inside the spec dir, so they're cleaned along with everything else. ✅ No code change needed; plan doesn't mention this.

### E16. `acorn list` / `acorn status` — do they need updating?

**Plan §12 question 2:** Defers this. ✅ Acceptable for v1. Output mode display is a nice-to-have but not in AC.

### E17. Backwards-compatible heredoc rendering — empty-block case

**Critical edge case:** When `output_mode="single"`:
- `three_block=""` (plan §3.1.4).
- awk substitutes `__THREE_ARTIFACT_BLOCK__` with empty string.
- The placeholder line becomes blank.
- The original heredoc had no `__THREE_ARTIFACT_BLOCK__` — the plan ADDS it.

**Resulting PROMPT.md in single mode:** has 2 extra blank lines compared to today's output (the placeholder line + adjacent blank line collapse to nothing).

**Implication:** Single-mode PROMPT.md is NOT byte-identical to today's output. Plan §3.1.4 acknowledges: "modulo two extra blank lines, harmless". ✅ But: the regression test should explicitly diff and confirm "harmless" — i.e., same content, only whitespace differs. Add to regression test.

### E18. `validate_prompt_md` after the change

**Verification (lines 1672-1676):**
```bash
validate_prompt_md() {
  local prompt_path="$1"
  grep -q 'PLANNING METHODOLOGY — MANDATORY INSTRUCTIONS' "$prompt_path" || return 1
  return 0
}
```

This validator only checks for the methodology anchor. It does NOT check for the three-artifact block. So in three-artifact mode, if `three_artifact_instructions()` is broken and emits nothing, `validate_prompt_md` still passes. **Recommendation:** Add an additional check for `__THREE_ARTIFACT_BLOCK__` (negative — should NOT be present, indicating substitution succeeded) when in three-artifact mode. Or check for "THREE-ARTIFACT OUTPUT MODE" header.

### E19. Pipeline mode + output mode matrix coverage

| pipeline_mode | output_mode | Tested? |
|---|---|---|
| full | single | ⚠️ Indirectly (existing tests) |
| full | three-artifact | ✅ Test 5 |
| lite | single | ✅ Test 3 |
| lite | three-artifact | ✅ Test 4 |
| quick | single | ⚠️ Not directly tested in new file |
| quick | three-artifact | ✅ Test 6 |

**Gap:** `quick + single` and `full + single` are not explicitly tested. Add: `test_planning_block_quick_single_mode_omits_block` and `test_planning_block_full_single_mode_omits_block`.

### E20. The `__SPEC_PATH__` token inside `three_artifact_instructions()` is bash-quoted

**Verification:** The plan's `three_artifact_instructions()` heredoc uses `<<'THREE_ARTIFACT_EOF'` (single-quoted), which means `$VAR`, `\n`, etc. are NOT expanded. Only literal text is emitted. ✅ Correct — substitution happens later via sed.

### E21. Order-of-operations: `ACORN_OUTPUT_MODE` env var read BEFORE arg parsing

**Plan §3.1.6:** `output_mode="${ACORN_OUTPUT_MODE:-single}"` is read inside `cmd_create` AFTER the arg-parse loop.
**Concern:** If a future flag like `--output-mode` is added, it should take precedence over the env var. Plan defers `--output-mode` flag (§12 q3). Acceptable.

### E22. Cross-cutting risk — plan's "Total ~350 net lines" estimate

**Verification:** Reading the plan carefully:
- `bin/acorn` changes: ~120 lines
- `test/test_three_artifact.sh`: ~210 lines (counting boilerplate from line 502-714)
- `claude/commands/acorn.md`: ~30 lines

Total ~360. Plan says ~350. ✅ Close enough.

### E23. Bash version compatibility

**Recon notes:** "bash 4+". Plan's syntax (`${var:-default}`, `case`, `local`, `printf`) is bash-3+ compatible. ✅ No issue.

**Concern:** The plan's `awk -v block="$three_block"` syntax is POSIX awk, compatible with both gawk (Linux) and BWK awk (macOS). ✅ But the gsub backslash issue is universal across awks.

### E24. Telemetry / observability

Plan doesn't add any logging beyond the user-visible "Output mode: $output_mode" echo. **Acceptable for v1.** A future enhancement could log to a structured file for audit. Defer.

### E25. Internal contradiction check

Plan §3.1.4 says heredoc placement: "BEFORE the existing line: `- Write the final spec to __SPEC_PATH__/plans/SPEC.md`".

But plan §3.1.2's `three_artifact_instructions()` heredoc itself ends with: "Your final response must list all three paths: Done. Output: __SPEC_PATH__/plans/SPEC.md + __SPEC_PATH__/plans/PLAN.md + __SPEC_PATH__/plans/TASKS.md".

So the agent prompt in three-artifact mode contains BOTH:
1. The injected three-artifact block saying "final response must list all three paths".
2. The original heredoc line saying `Your final response must be ONLY: "Done. Output: __SPEC_PATH__/plans/SPEC.md"`.

**These contradict each other.** The plan says (line 339 of draft.md): "the final-response format guidance is overridden by the inline instructions". But **a contradiction in a prompt is not a robust override mechanism** — the LLM may follow either or both.

**Resolution required:** In three-artifact mode, the original "Your final response must be ONLY..." line should either be (a) replaced by the new instruction, OR (b) the three-artifact block should explicitly say "OVERRIDE the previous final-response instruction with: ...".

Recommend (b) with explicit override language. **This is a real defect, must fix.**

---

## 5. Prioritized Findings Summary

### Must-fix before merge (Severity: High)

| # | Finding | Where | Fix |
|---|---|---|---|
| MF1 | `awk gsub` interprets backslashes — silently corrupts injected block | §3.1.4, §6.5 | Use `sed '/__THREE_ARTIFACT_BLOCK__/r block_file'` or `awk` with `getline < file`. See §F2. |
| MF2 | Final-response prompt contradicts itself in three-artifact mode | §3.1.4 + §3.1.2 | Add explicit "OVERRIDE: …" language in three_artifact_instructions, OR replace the original final-response line via second sed substitution. See §E25. |
| MF3 | SPEC.md trim instructions reference invented section numbers | §3.1.2 | Use section NAMES not numbers, OR define the canonical SPEC.md template numbers in the prompt. See §A11. |
| MF4 | Phase 4 dependency listed as Phase 2 but actually requires Phase 3 | §8 | Update phase dependency. See §A9. |
| MF5 | Pre-existing PROMPT.md skips regeneration; meta.json says three-artifact but PROMPT.md is single → silent failure | §3.1.6 (cmd_create flow) | Detect mode mismatch in cmd_create and warn or refuse. See §E8. |

### Should-fix before merge (Severity: Medium)

| # | Finding | Where | Fix |
|---|---|---|---|
| SF1 | Plan only shows lite-mode heredoc edit in detail; full and quick are "same edit" but have different structures | §3.1.4 | Show all three modified heredoc snippets explicitly. See §A4. |
| SF2 | Tests don't cover `cmd_spec_complete` warnings (only `cmd_approve`) | §3.2 | Add parallel test for cmd_spec_complete. See §E13. |
| SF3 | `validate_prompt_md` doesn't check three-artifact block was substituted | §3.1.4 / §6 | Add positive check for "THREE-ARTIFACT" string when `output_mode=three-artifact`. See §E18. |
| SF4 | Tests for quick+single, full+single not present | §3.2 | Add 2 tests for omit-block in quick and full single modes. See §E19. |
| SF5 | TASKS.md verify command working dir is unspecified | §3.1.2 | Specify "from repo root" in three_artifact_instructions. See §A12. |
| SF6 | Plan §3.3 docs target line range slightly off; "Examples" section doesn't exist | §3.3 | Use "after Project layout section" anchor. See §A10. |
| SF7 | `cmd_approve` doesn't verify PLAN.md/TASKS.md are non-empty (only that they exist) | §3.1.8 | Use `[ -s "$dir/plans/PLAN.md" ]` instead of `[ -f ... ]`. See §E6. |
| SF8 | TASKS.md schema lacks version marker | §3.1.2 | Add `# acorn-tasks-schema: v1` comment to schema. See §E10. |
| SF9 | Validation case statement runs on every CLI invocation, can spam warnings | §3.1.1 | Move validation into cmd_create only, or accept noise. See §A2. |

### Nice-to-fix (Severity: Low)

| # | Finding | Where | Fix |
|---|---|---|---|
| NF1 | `write_meta_json` not atomic; concurrent writes can race (pre-existing) | §3.1.7 | Add temp+mv pattern. Pre-existing concern; defer. |
| NF2 | No documented procedure for upgrading single-mode spec to three-artifact | §6.3 | Document `rm PROMPT.md && re-create` recovery. See §E5. |
| NF3 | Quick mode + three-artifact may produce lower-quality PLAN/TASKS | §2.3 | Add note in docs warning users. See §E7. |
| NF4 | Test mocks brittle (closure over `$dir`) | §3.2 (test 9) | Use global env var or explicit local. See §F13. |
| NF5 | Risk R4 makes unverifiable claim about Forge `spec-metadata-extract.sh` | §10 | Lower confidence; add deferred follow-up. See §F14. |
| NF6 | No escape hatch for adding `--output-mode` CLI flag in v2 | §12 q3 | Plan structure already supports this; no fix needed, just doc note. |

### Non-issues (claims confirmed correct)

- All function line numbers accurate (§F1).
- Heredoc placement between "ZERO questions" and "Write the final spec…" is correct (§F4).
- Schema fidelity vs PROMPT.md AC #3, #4 is exact or richer (§F16).
- Substitution order (awk before sed) is correct (§F2).
- Backwards-compat via `jq // "single"` is robust (§A7).
- Single-mode behavior remains byte-equivalent modulo whitespace (§E17).
- No new dependencies introduced (§E22, §F2 mitigation uses sed which is already a dep).
- Forge-coupling check passes — `three_artifact_instructions()` text is forge-agnostic.
- `cmd_clean` already removes new files (no change needed) (§E15).
- Security: no injection vectors via env var or issue body (§E11, §E12).

---

## 6. Recommended Resolutions for Stage 3 Final Spec

The Final Spec agent should:

1. **Replace the awk-based substitution mechanism** with a file-based approach. Suggested:
   ```bash
   local block_file=""
   if [ "$output_mode" = "three-artifact" ]; then
     block_file="$(mktemp)"
     three_artifact_instructions > "$block_file"
   fi
   if [ -n "$block_file" ]; then
     cat <<'METHODOLOGY_EOF' \
       | sed -e "/__THREE_ARTIFACT_BLOCK__/{r ${block_file}" -e 'd}' \
       | sed "s|__SPEC_PATH__|${spec_path}|g"
     # ...heredoc...
     METHODOLOGY_EOF
     rm -f "$block_file"
   else
     cat <<'METHODOLOGY_EOF' \
       | sed '/__THREE_ARTIFACT_BLOCK__/d' \
       | sed "s|__SPEC_PATH__|${spec_path}|g"
     # ...heredoc...
     METHODOLOGY_EOF
   fi
   ```
   This avoids awk's backslash-mangling and uses only sed (already a dep).

2. **Show the modified heredoc for ALL THREE modes** in §3.1.4. Include line-numbered before/after diffs.

3. **Replace SPEC.md trim section numbers with section names** in `three_artifact_instructions()`. Use the canonical names: "Requirements Traceability Matrix", "Functional Requirements", "Implementation Plan", "Testing Strategy", "Risk Register", "Pi Model Recommendation".

4. **Add explicit "OVERRIDE" language** to the three-artifact block to resolve the contradicting final-response instruction:
   ```
   IMPORTANT: This OVERRIDES the prior "Your final response must be ONLY: ..." instruction.
   In three-artifact mode, your final response must be:
   "Done. Output: __SPEC_PATH__/plans/SPEC.md + __SPEC_PATH__/plans/PLAN.md + __SPEC_PATH__/plans/TASKS.md"
   ```

5. **Add `cmd_create` mode-mismatch detection:**
   ```bash
   if [ -f "$prompt_path" ] && [ -f "$dir/meta.json" ]; then
     local recorded_om
     recorded_om="$(jq -r '.output_mode // "single"' "$dir/meta.json" 2>/dev/null || printf 'single')"
     if [ "$recorded_om" != "$output_mode" ]; then
       warn "PROMPT.md exists with output_mode=$recorded_om but env requests $output_mode; PROMPT.md NOT regenerated. Delete PROMPT.md to regenerate."
     fi
   fi
   ```

6. **Update Phase 4 dependency** in §8 from "Phase 2" to "Phase 3".

7. **Add tests:**
   - `test_planning_block_quick_single_mode_omits_block`
   - `test_planning_block_full_single_mode_omits_block`
   - `test_spec_complete_warns_on_missing_plan_in_three_artifact_mode`
   - `test_three_artifact_instructions_emits_nonempty`
   - `test_cmd_create_warns_on_mode_mismatch`

8. **Use `[ -s ... ]` instead of `[ -f ... ]`** in approve/spec-complete warnings to catch empty/truncated files.

9. **Add schema version comment** to TASKS.md output: `# acorn-tasks-schema: v1` at the top.

10. **Specify "verify commands run from repo root"** in `three_artifact_instructions()` TASKS.md schema description.

---

## 7. Conclusion

The plan is a strong starting point with **one critical mechanical defect** (awk-gsub backslash handling) and **one structural defect** (contradicting final-response prompt). Both must be fixed in the Final Spec.

Beyond those two, the plan correctly identifies all integration points, accurately references existing code, and proposes a backwards-compatible, upstreamable design. With the must-fix items addressed, this is a clean implementation candidate suitable for a single PR.

**Estimated effort:** 4-6 hours of focused work to fix all must-fix items, ~2 hours for should-fix items, manual smoke test ~30 min.

**Recommended Pi model for implementation:** `codex` (per the plan's own decision criteria — specific files, named functions, pattern-following, < 8 files, includes test commands).
