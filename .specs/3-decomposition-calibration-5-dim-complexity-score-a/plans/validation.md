# Validation Report — Decomposition-Calibration: 5-Dim Complexity Score

**Plan validated:** `plans/draft.md`
**Build base:** `forge-acorn-live-base` @ `d83a162` (confirmed checked-out branch; `bin/acorn` = 4227 lines)
**Verdict:** The plan is **strong and largely accurate** — line numbers, function locations, contract details, and the deterministic-core design all check out against the live source. It is APPROVE-WITH-FIXES: a small number of concrete defects (one factual error in the quick-mode section numbering, one self-inconsistent test assertion, and one soft-coverage gap on Requirement 1) must be corrected before implementation. None are architectural; all are localized.

---

## 1. Requirements Coverage Matrix

| Req | Requirement (PROMPT.md) | Addressed? | Where | Testable/Specific? | Gap |
|---|---|---|---|---|---|
| **R1** | 5-dim score (1–3 each) → sum → band LOW 5-7/MED 8-11/HIGH 12-15, recorded in SPEC header, produced automatically in `issue plan`/authoring path | **Partial** | §8 (planning-block injection, all 3 modes) + §5 (`complexity_band`) | Band math: YES (T1–T3). Authoring-path emission: **SOFT** — only the *instruction text* is tested (T15), no gate/test proves an actual SPEC.md contains the score | **GAP-1 (Med):** "produced automatically" is instruction-only. No `stage_manifest` entry requires `## Complexity Score` in SPEC.md; T15 asserts the planning-block *contains the instruction* (near-tautological), not that the authoring path emits a score. See §4/GAP-1. |
| **R2** | HIGH (≥12) → MUST PROPOSE decomposition unless atomic (record justification) | **Yes (advisory)** | §7.2 (`cmd_issue_split` HIGH `warn`), §8.2 (agent rule + `## Proposed Decomposition`), `atomic_justification` field §4 | Split path: YES (T12/T13). Authoring path: soft (agent-judgment) | Acceptable — PROMPT says "MUST PROPOSE", not "MUST block". R5 acknowledges. |
| **R3** | Size gate: ~800 LOC OR >8 files → "decomposition review before build", independent of band | **Yes** | §5.2 `check_size_thresholds`, §5.3 `size_flag`, §8.2 `size_review` | YES — T4/T5/T6/T8; T8 explicitly proves band-independence | Covered well. |
| **R4** | Preserve manual `split` path + `should_split`/`reasoning`/`sub_issues` contract; additive extension | **Yes** | §4 (nested `complexity` obj), §6.2 (validator untouched, still line 3291), §9 degrade-not-break | YES — T9/T11 + full `test_split.sh` regression | Strong. Validator at line 3291 confirmed unchanged. |
| **G1** | Do NOT touch pre-Stage-0 `/clarify` code | **Yes** | §10.3 out-of-scope note | N/A | No clarify edits proposed. Correct. |
| **G2** | Config-over-hardcoding: all cutoffs env-overridable, no magic numbers | **Yes** | §3 (4 env vars), §8.1 (sed-injected cutoffs) | YES — T2/T6 config-override tests | Names differ from recon suggestions (harmless, see §2). |
| **G3** | No-stub/accurate: scorer derives from real content; honest fallback | **Yes** | §4 provenance table, §9 fallbacks (`// 0`, `case` guards) | Partial — fallback behavior asserted indirectly | Reasonable. |
| **G4** | Prove-it-first negative controls; NOT tautological green-by-construction | **Mostly** | §10.2 red baseline, §10.1 anti-tautology note (T7/T8 compute band from raw dims; T12+T13 pair) | T7/T8/T12/T13 are genuine. T15 is weak (see GAP-1). | **GAP-1 partially undermines G4** for the authoring path. |
| **G5** | Deploy out of scope; branch artifacts + PR-to-fork only | **Yes** | §12 | N/A | Correct. |

**Net:** All four functional requirements are addressed. R3/R4 are excellently covered with genuine negative controls. R1 has a real coverage weakness on the "produced automatically" clause (instruction-only, no enforcing gate, no true end-to-end test) — the most substantive gap and the one most in tension with the PROMPT's own gate-test-drives-real-code doctrine.

---

## 2. Codebase Fact-Check

Every factual claim in the plan was checked against `bin/acorn` on the live base. Results:

| Plan claim | Verified? | Actual |
|---|---|---|
| `analyze_issue_for_split()` at ~line 3208, spans 3208–3295 | ✅ | Defined line 3208, closes line 3295 |
| 3-key validator at line 3291: `has("should_split") and has("reasoning") and has("sub_issues")` | ✅ | Exact match, line 3291 |
| JSON parse/`die` guard at line 3288 | ✅ | `[ -n "$json" ] \|\| die ...` at line 3288 |
| Prompt heredoc is single-quoted `<<'SPLIT_PROMPT_EOF'` (no expansion) | ✅ | Line 3215 `cat <<'SPLIT_PROMPT_EOF'` |
| Existing JSON schema block in prompt (lines 3230–3237) | ✅ | Present, exactly the 3-key shape |
| `format_split_recommendation()` at 3299–3331; insert after "Reasoning:" (3311) before `if [ "$should_split" = "true" ]` (3313) | ✅ | Def 3299, "Reasoning:" echo 3311, `if` at 3313, closes 3331 |
| `cmd_issue_split()` at ~3503; `analyze_issue_for_split` call line 3556; `format_split_recommendation` call line 3559; `should_split` check at 3562 | ✅ | Def 3503, call 3556, format 3559, `should_split="..."` 3563, `if` 3565 |
| Env vars declared 1–16, `ACORN_OUTPUT_MODE` at line 16, insert new vars after | ✅ | `ACORN_OUTPUT_MODE` at line 16 (note: lines 14–15 are `_SHOW_DEPS`/`_LIST_NWO` between retry vars and OUTPUT_MODE — insertion after 16 is clean) |
| `planning_block_lite()` at 1275, sed pipeline 1284–1289, terminal `\| sed "s\|__MODE__\|..."` | ✅ | Def 1275, `cat <<'METHODOLOGY_EOF'` 1284, sed lines 1285–1289, `__MODE__` terminal at 1289 (no trailing `\`) |
| Lite Pi Model Recommendation is section **6** at line 1541 | ✅ | `6. **Pi Model Recommendation**` line 1541 |
| Full Pi Model Recommendation is section **6** at line 1235 | ✅ | `6. **Pi Model Recommendation**` line 1235 |
| Quick Pi Model Recommendation is section **6** (plan §8.2 says "renumber to 7" uniformly) | ❌ **FACT ERROR** | Quick numbers it section **5** at line 1750 (quick's final-spec prompt has only sections 1–5). Plan's blanket "insert before section 6, renumber Pi Model to 7" is WRONG for quick. See ERROR-1. |
| `validate_prompt_md()` at ~1892; sentinel grep `__SPEC_PATH__\|__RETRY_BUDGET__\|...` | ✅ | Def 1886, sentinel grep at line 1893 (exact token list matches) |
| `stage_manifest`/`validate_stage_artifacts` check SPEC.md with `^## ` header; any-line grep | ✅ | `validate_stage_artifacts` line 162 uses `grep -E -q -- "$header"` (matches any line); `## Complexity Score` satisfies it — no conflict |
| `write_meta_json()` at ~2180, runs at `cmd_create` time before recon | ✅ | Def 2180; §8.4 rationale for not using meta.json is sound |
| `info`/`warn`/`die` defs (warn→stderr) | ✅ | Lines 39–41; `warn` writes to `>&2`. Tests capturing `2>&1` will see it |
| Test harness sources via `eval "$(sed '/^main "\$@"/d' ...)"`; mocks via `export -f` | ✅ | Confirmed in `test/test_split.sh` |
| `test_split.sh` mocks `claude` returning legacy 3-key JSON (backward-compat proof) | ✅ | Lines 103–108 etc.; existing `cmd_issue_split` tests mock `gh_issue_json`, `safe_repo_main`, `require_cmds`, `analyze_issue_for_split` (lines 179–201) |
| `test_planning_block_clarify.sh` / `test_auto_trigger_clarify_hint.sh` are pre-existing failures (clarify backed out) | ✅ | Both files exist; clarify functions absent from live base |
| Env-var name divergence: recon suggested `ACORN_COMPLEXITY_LOC_THRESHOLD`; plan uses `ACORN_LOC_DECOMP_THRESHOLD` | ⚠️ Harmless | No external contract binds these names; plan is internally consistent. Note only. |

**Fact-check conclusion:** One genuine factual error (ERROR-1, quick-mode section numbering). Everything else the plan asserts about the codebase is accurate to the line. The plan does NOT reinvent any existing utility — it correctly reuses the integer-guard `case` idiom, the `printf '%s' | jq` pattern, `warn`/`die`, the sed-substitution planning-block mechanism, and the `has()` validator.

---

## 3. Ambiguity Audit

Information a developer would need but the plan leaves under-specified:

**AMB-1 (Med) — sed pipeline continuation not spelled out (§8.1).** The existing terminal sed line in each block is `| sed "s|__MODE__|${mode}|g"` with **no trailing backslash** (verified line 1289 lite, and structurally identical in full/quick). The plan's §8.1 shows "New lines to append" beginning with `| sed ...` but never states that the implementer must first **add a `\` to the current `__MODE__` line** to continue the pipeline. An implementer pasting the four new lines literally after an unbackslashed `__MODE__` line produces a broken command (the new `| sed` lines become separate no-op commands or a syntax error under `set -e`). Fix: explicitly instruct "append `\` to the existing `__MODE__` sed line, then add the four new sed lines, the last WITHOUT a trailing backslash."

**AMB-2 (Med) — quick-mode differs structurally, not just in numbering.** Quick's final agent is the "Spec Writer" (line 1721), not "Final Spec agent", and has a *different* 5-section list (no Validation Resolution Log). §8.2's instruction to "insert immediately before `6. **Pi Model Recommendation**`" cannot be applied by literal string match in quick (where the string is `5. **Pi Model Recommendation**`). The implementer needs per-mode anchors, not one blanket instruction. (Related to ERROR-1.)

**AMB-3 (Low) — T12/T13/T14 mocking scope for `cmd_issue_split` is not enumerated.** To exercise `cmd_issue_split`, the test must mock `gh_issue_json`, `safe_repo_main`, `require_cmds`, AND `analyze_issue_for_split` (the exact set used by existing `test_split.sh` lines 179–201; `render_comments_block` runs real and needs the `gh_issue_json` mock to return valid JSON with a `.comments` array). The plan says only "mock `analyze_issue_for_split`". Also unspecified: the HIGH-band mock should return `should_split:false` so control flow hits the early `return 0` after the `warn` — otherwise `cmd_issue_split` reaches the non-interactive `die` (line 3584) or needs `--yes` + a `create_sub_issues` mock. State this to keep the test simple and deterministic.

**AMB-4 (Low) — insertion order of `## Complexity Score` vs `## Pi Model Recommendation` in SPEC.md.** Both instructions say "at the top of SPEC.md." §8.2 says Complexity Score goes "before `## Pi Model Recommendation`," and Pi Model says "before `## 1. Requirements Traceability Matrix`." The intended final top-of-file order (Complexity Score → Pi Model → Section 1) is inferable but never stated as a single ordering rule. Low risk; worth one sentence.

**AMB-5 (Low) — "≤MED sub-specs" is defined only in prose.** The agent instruction says decompose into "≤MED sub-specs" but gives the agent no mechanical way to verify a proposed sub-spec is ≤MED (it would have to re-score each). Acceptable for an advisory instruction, but note it is judgment, not enforced.

**AMB-6 (Low) — env vars consumed across multiple functions; guard placement.** §9 correctly notes thresholds are used in `complexity_band`/`check_size_thresholds` and adds in-helper `case` guards. But the same env vars are ALSO read directly inside `enrich_complexity` (§5.3: `[ "$loc" -gt "$ACORN_LOC_DECOMP_THRESHOLD" ]`). If a threshold env var is non-integer, that bare `[ -gt ]` in `enrich_complexity` errors under `set -e` even though the helpers are guarded. The guard must cover the `enrich_complexity` direct comparisons too (or route them through the guarded helpers). The plan half-addresses this; make it explicit.

---

## 4. Edge Cases, Risks & Defects

### Concrete defects to fix before implementation

**ERROR-1 (High severity — factual) — quick-mode Pi Model Recommendation is section 5, not 6.** Plan §8.2: "Insert a numbered section immediately before '6. **Pi Model Recommendation**' (renumber Pi Model Recommendation to 7)." Verified: full=6 (1235), lite=6 (1541), **quick=5 (1750)**. Applying the plan literally to quick either fails to match or mis-numbers the sections. **Fix:** For quick, insert the new Complexity Score section as **#5** and renumber Pi Model Recommendation to **#6**. Full/lite become #6→#7 as written.

**DEFECT-2 (Med — test self-inconsistency) — T15 asserts a substring that a correct implementation will not emit.** T15 (§10.1) says assert the rendered block "contains … substituted band cutoffs (e.g. `≤ 7`/`12`)". But §8.2's instruction text expresses HIGH as `sum > __COMPLEXITY_MED_MAX__`, which substitutes to `> 11` (MED_MAX default 11) — the literal string `12` never appears. Asserting `"12"` would FAIL against the correct output. **Fix:** assert on the actually-substituted tokens — e.g. `≤ 7` (LOW_MAX) and `> 11` (MED_MAX) — and assert absence of the raw `__COMPLEXITY_LOW_MAX__`/`__COMPLEXITY_MED_MAX__` placeholders. (The intent — prove cutoffs are injected, not hardcoded — is right; the expected value is wrong.)

**GAP-1 (Med — coverage/anti-tautology) — R1 "produced automatically" has no enforcing gate and no genuine end-to-end test.** The authoring-path score is emitted purely because the planning block *tells the agent to*. Two consequences: (a) `stage_manifest` still only requires `^## ` in SPEC.md, so a SPEC.md with no `## Complexity Score` block passes the gate — the requirement's "produced automatically" is not enforced; (b) T15 only checks that the *instruction string is present in the planning block* — i.e. it re-asserts the text the implementer just added, which is close to the "green-by-construction / re-asserts its own inputs" anti-pattern the PROMPT explicitly forbids for the gate. A true e2e test (run the pipeline, inspect a produced SPEC.md) is not feasible in the shell harness because the authoring path is a live Claude session. **Recommended:** EITHER (i) strengthen `stage_manifest` for the SPEC.md stage to also require `## Complexity Score` (a real, enforceable gate on the artifact — this is the strongest fix and directly satisfies "produced automatically"), OR (ii) explicitly document in the SPEC that authoring-path emission is advisory/agent-judgment and cannot be shell-gated, so reviewers do not mistake T15 for an end-to-end guarantee. Option (i) is preferred and low-cost.

### Edge cases — handling assessment

| Edge case | Plan handling | Assessment |
|---|---|---|
| Model omits `complexity` block (every legacy mock) | `enrich_complexity` guard `jq -e '.complexity.dims \| objects'` → pass-through | ✅ Sound. Verified the guard is a strict no-op; T9/T11 lock it. |
| Dims present but null/out-of-range | `map(. // 0) \| add` | ✅ null→0. But **out-of-range** (e.g. dim=9) is NOT clamped — sum could exceed 15 and still map HIGH, which is acceptable (honest), though the prose claims "1–3". Minor; note that values are trusted, not validated. |
| `loc_estimate_total`/`files_estimate_total` missing/non-numeric | `// 0` + `case` guard → 0 → gate doesn't fire | ✅ Sound. |
| Non-integer threshold env var | §9 says guard in helpers | ⚠️ Incomplete — see AMB-6: `enrich_complexity`'s direct `[ -gt ]` comparisons also need the guard. |
| `set -e` trips on `[ ] && x=true` | §5.3 mandates explicit `if…then…fi` form | ✅ Correct call; R2 mitigates. |
| HIGH band but <2 sub_issues in split path | `warn` emitted before early-return; advisory both ways | ✅ Intentional & correct (§9). |
| `claude`/`jq` failure | Existing `die` fires before enrichment | ✅ Unchanged path. |
| Unsubstituted placeholder leaks to PROMPT.md | Sentinel extended §8.3; T16 | ✅ Verified sentinel at line 1893; the 4 new tokens must be added exactly. |
| `## Complexity Score` collides with manifest `^## ` | No collision (any-line grep) | ✅ Verified `validate_stage_artifacts` line 172 greps any line. |
| PROMPT.md now carries instruction strings `## Complexity Score` / `## Proposed Decomposition` as literal `##` headings | Not discussed | ⚠️ Low risk. PROMPT.md already contains many `##` instruction headings; nothing parses PROMPT.md expecting a fixed top-level heading set. Note only. |
| `format_split_recommendation` extra stdout lines break a consumer | Only caller is `cmd_issue_split` (3559), which does not parse the output | ✅ Safe. |
| `≤` / `⚠` unicode in heredocs & sed | Chars are in heredoc body / replacement RHS only, not in regex LHS | ✅ Safe; file already uses unicode (`—`, box-drawing). |

### Security

No new security surface. Inputs are LLM-produced JSON already flowing through `jq` (no `eval` of model output; the plan does not `eval` any model field). Threshold env vars are integer-guarded (once AMB-6 is closed), so no injection via env into arithmetic. sed substitutions inject only integer threshold values (guarded) into instruction text — no shell metacharacter path. `--argjson` is fed only the literal strings `true`/`false`/computed integers (R8 pins this via T4–T6). **No injection, auth-bypass, or data-exposure concerns.**

### Ordering / internal-contradiction check

- Implementation order (§11) is sound: helpers (step 2) before `analyze_issue_for_split` enrichment (step 3) before display/surface (4/5); threshold locals (step 6, depends on env vars step 1) before sentinel (step 7). Dependencies stated correctly.
- No internal contradiction between the deterministic split-path math (§5/§6) and the agent-judgment authoring path (§8) — the plan is explicit that these are two sites sharing only prose rubric + env cutoffs (R4/R6). This is a deliberate, defensible asymmetry, not a bug.

---

## 5. Summary — Required Fixes Before Implementation

1. **ERROR-1 (High):** Quick-mode Pi Model Recommendation is section **5** (line 1750), not 6. Insert Complexity Score as #5, renumber Pi Model to #6 in quick only. Full/lite are #6→#7 as written.
2. **DEFECT-2 (Med):** Fix T15 expected substring — assert `> 11` (not `12`) and `≤ 7`, plus absence of raw placeholder tokens.
3. **GAP-1 (Med):** Strengthen the SPEC.md `stage_manifest` header to require `## Complexity Score` (enforceable gate for R1 "produced automatically"), OR explicitly document that authoring-path emission is advisory and T15 is not an e2e guarantee.
4. **AMB-1 (Med):** Spell out the sed-pipeline continuation (add `\` to the existing `__MODE__` line before appending the four new sed lines).
5. **AMB-6 (Med):** Ensure threshold integer-guards also cover the direct `[ -gt ]` comparisons inside `enrich_complexity`, not only the two helpers.
6. **AMB-2/AMB-3 (Low-Med):** Give per-mode anchors for the planning-block insertion (quick differs structurally); enumerate the full mock set for the `cmd_issue_split` surfacing tests and pin the HIGH mock to `should_split:false`.

**Everything else in the plan is accurate and implementation-ready.** The deterministic-bash-core / LLM-estimates-only design is the right anti-tautology decision, the backward-compat strategy is verified safe (validator at line 3291 untouched; `enrich_complexity` pass-through guard is a strict no-op), config-over-hardcoding is fully honored, and the split-path negative controls (T4–T9, T12/T13 pairing) are genuine. Address the six items above and the spec is ready for a codex-class implementer.

