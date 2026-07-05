# DONE: 3-decomposition-calibration — 5-Dim Complexity Score

**Branch:** `3-decomposition-calibration`  
**Base:** `forge-acorn-live-base` @ `d83a162`  
**Spec:** `.specs/3-decomposition-calibration-5-dim-complexity-score-a/plans/SPEC.md`

---

## Files Changed

| File | Lines | Summary |
|---|---|---|
| `bin/acorn` | 4227 → 4497 (+270) | Additive change: env vars, 3 pure helpers, extended split path, 3 planning blocks, validate_prompt_md sentinel, stage_manifest gate |
| `test/test_complexity_score.sh` | 0 → 534 (new) | 18 test functions, 63 assertions covering T1–T18 |

No other files modified. No new runtime dependencies. No build step required.

---

## Env Var Names + Defaults

| Env Var | Default | Purpose |
|---|---|---|
| `ACORN_COMPLEXITY_LOW_MAX` | `7` | Upper bound (inclusive) of LOW band |
| `ACORN_COMPLEXITY_MED_MAX` | `11` | Upper bound (inclusive) of MED band |
| `ACORN_LOC_DECOMP_THRESHOLD` | `800` | LOC threshold for size-review flag |
| `ACORN_FILES_DECOMP_THRESHOLD` | `8` | File-count threshold for size-review flag |

Band ladder: LOW ≤ 7 < MED ≤ 11 < HIGH. All 4 vars use `${VAR:-default}` house pattern, integer-guarded via `case … [0-9]` in all consumption sites. No bare magic numbers anywhere in logic.

---

## Gate Results

### (a) `test/test_complexity_score.sh` — 63 passed, 0 failed

```
T1: complexity_band boundaries          — 6/6 PASS
T2: complexity_band config override     — 2/2 PASS
T3: complexity_band non-numeric         — 2/2 PASS
T4: check_size_thresholds LOC gate      — 2/2 PASS
T5: check_size_thresholds files gate    — 2/2 PASS
T6: check_size_thresholds config        — 1/1 PASS
T7: enrich_complexity computes band     — 3/3 PASS (anti-tautology: computes from raw dims)
T8: enrich_complexity size indep band   — 3/3 PASS (anti-tautology: LOW band + 950 LOC = size_review true)
T9: enrich_complexity legacy pass-thru  — 3/3 PASS
T10: analyze extended complexity        — 4/4 PASS
T11: analyze backward-compat            — 3/3 PASS
T12+T13: HIGH surfacing (paired)        — 2/2 PASS (T12 emits, T13 silences)
T14: size-review surfacing              — 1/1 PASS
T15: planning blocks scoring (3 modes)  — 18/18 PASS (each mode: header + 5-dim + cutoffs + no raw placeholders)
T16: validate_prompt_md sentinel        — 5/5 PASS
T17: stage_manifest SPEC.md gate        — 4/4 PASS (GAP-1: SPEC without ## Complexity Score FAILS)
T18: non-integer threshold graceful     — 2/2 PASS
```

### (b) Prove-it-first RED baseline

Run `test_complexity_score.sh` against live-base (pre-fix) `bin/acorn`:

```
T1–T6: command not found → exit 127 (all helpers undefined on live base)
```

This demonstrates that T1–T6, T7–T10, T12, T14–T17 ALL genuinely fail without the fix — no green-by-construction tautology. T7/T8 compute band/flag from raw dims (expected values never present in input). The T12/T13 pair is only jointly satisfiable by band-conditional code (live base satisfies neither jointly: it either crashes silently in the test or both fail).

### (c) Regression suite — full green

| Test | Result |
|---|---|
| `bash -n bin/acorn` | SYNTAX OK |
| `test/test_split.sh` | **22 passed, 0 failed** |
| `test/test_recon_completeness.sh` | **8 passed, 0 failed** |
| `test/test_three_artifact.sh` | **4 passed, 0 failed** |

The existing `analyze_issue_for_split` mock in `test_split.sh` returns legacy 3-key JSON (no `.complexity`), exercising the `enrich_complexity` pass-through path. All 22 tests pass unchanged. No fixture changes needed.

---

## Revert Surface

Revert is a single commit. Changes are additive and namespaced:
- New functions: `complexity_band`, `check_size_thresholds`, `enrich_complexity` (colocated above `analyze_issue_for_split`)
- New env vars: 4 lines after `ACORN_OUTPUT_MODE`
- 3 planning block extensions: locals + sed lines + `## Complexity Score` instruction
- `stage_manifest`: one additional manifest line
- `validate_prompt_md`: 4 additional placeholders in sentinel grep
- `format_split_recommendation`: additive complexity display block (guarded)
- `cmd_issue_split`: additive `warn` block (guarded)

Zero residual state — no DB, no files created outside `bin/acorn`.

---

## Honest Notes / Assumptions / Fallbacks

- **Authoring-time score is model-judgment, not deterministic** — the planning-block `## Complexity Score` instruction is prose. The deterministic core (bash helpers) governs the machine-readable `acorn issue split` path only. This is by design; the PROMPT says "produced automatically" which the `stage_manifest` gate enforces (SPEC.md MUST contain the block), but the actual numbers are agent-produced. Risk R6 in spec.

- **Decomposition is advisory, not enforced** — HIGH band triggers "MUST PROPOSE" warnings but does not hard-block a build. Risk R5 in spec; a future follow-up could parse `decomposition: required` + absence of `## Proposed Decomposition` and hard-fail.

- **Rubric prose is duplicated** across the split prompt and 3 planning blocks (dim-name static text only). Thresholds are single-sourced from env (sed-injected). The spec accepts this as reasonable for a single-file bash architecture (Risk R4).

- **Dim values are trusted, not clamped** — if a model returns a dim of 9, it maps honestly to HIGH (no fabrication, no crash). Documented as edge-case behavior.

- **Honest fallback for unestimable dims**: the model is instructed to use `2` (moderate). The test helpers map null/missing dims to `0` via `jq map(. // 0)`. If the entire `.complexity` block is absent, the pass-through guard fires and the JSON is unchanged.

- **Did NOT touch pre-Stage-0 `/clarify` code** (PROMPT Guardrail G1). Functions `auto_trigger_message`, `stage_manifest` pre0 entries, `validate_stage_artifacts` pre0, and `clarifications.md` are all out of scope and untouched.

- **Did NOT deploy** (PROMPT Guardrail G5). Branch artifacts only.
