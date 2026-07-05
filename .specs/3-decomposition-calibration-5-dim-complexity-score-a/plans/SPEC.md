# SPEC: Decomposition-Calibration — 5-Dim Complexity Score at Spec Time + HIGH-Must-Propose-Decomposition + LOC/Files Thresholds

**Repo:** `elliottagentdev/acorn` (our fork)
**Build base branch (MANDATORY):** `forge-acorn-live-base` @ `d83a162` (byte-exact live-deployed acorn; 4227-line `bin/acorn`). Do NOT base on fork/main.
**Scope:** Calibrate decomposition/complexity-scoring logic only. No unrelated refactors. Do NOT touch pre-Stage-0 `/clarify` code.
**Files touched:** `bin/acorn` (modify) + `test/test_complexity_score.sh` (create). 2 files. No new runtime deps, no build step.

## This Spec's Own Complexity Score

```
## Complexity Score
score: 8 (band MED)
dims: files_touched=2 LOC_estimate=2 novelty=1 context_depth=2 cross_module_fan_out=1
size_estimate: ~250 LOC, 2 files
decomposition: not-required
atomic_justification: Single-file additive change to one cohesive subsystem (decomposition scoring); splitting would fragment a tightly-coupled deterministic-core + wiring change. Strategist ruled LOW lane; scored MED at authoring due to the multi-site wiring (split path + 3 planning blocks).
```

---

## Pi Model Recommendation

suggested_pi_model: codex
suggested_pi_model_rationale: Spec names exact files, functions, line numbers, and test commands; pure pattern-following additive bash change to 2 files with no new interfaces or schemas beyond one additive JSON field.

---

## 1. Requirements Traceability Matrix

Requirements are drawn verbatim from `PROMPT.md` (§Requirements 1–4 and §Guardrails).

| # | Requirement (from PROMPT.md) | Addressed in SPEC section | Status |
|---|---|---|---|
| **R1** | 5-dim complexity score (each 1–3: `files_touched`, `LOC_estimate`, `novelty`, `context_depth`, `cross_module_fan_out`), sum→band (LOW 5-7 / MED 8-11 / HIGH 12-15), recorded in SPEC header, **produced automatically** in the `acorn issue plan` / spec-authoring path (not only manual split). | §3.5 (env cutoffs) · §3.2 (`complexity_band`) · §3.7 (planning-block injection, all 3 modes) · §3.8 (**`stage_manifest` gate** requiring `## Complexity Score` in SPEC.md — closes GAP-1) | **Covered** |
| **R2** | HIGH (≥12) → MUST PROPOSE decomposition into ≤MED sub-specs UNLESS genuinely atomic (record atomic-justification). Proposal surfaces at plan time. | §3.7 (agent rule + `## Proposed Decomposition`) · §3.6.2 (`cmd_issue_split` HIGH `warn`) · §3.3 (`decomposition_required`) · §3.4 (`atomic_justification` field) | **Covered (advisory — see Risk R5)** |
| **R3** | Size gate: estimate exceeds ~800 LOC OR >8 files → flag "decomposition review before build", **independent of the 5-dim band**. | §3.2 (`check_size_thresholds`) · §3.3 (`size_flag`) · §3.7 (`size_review` line) · Test T8 proves band-independence | **Covered** |
| **R4** | Preserve manual `acorn issue split` + existing `analyze_issue_for_split` JSON contract (`should_split`/`reasoning`/`sub_issues`); calibration is ADDITIVE, do not break consumers. | §3.4 (additive nested `complexity` object) · §3.3 (`enrich_complexity` pass-through guard) · §3.6.1 (validator at line 3291 untouched) · Tests T9/T11 + full `test_split.sh` regression | **Covered** |
| **G1** | DO NOT touch pre-Stage-0 `/clarify` code (out of scope). | §6 (out-of-scope note); no edits to any clarify function | **Covered** |
| **G2** | Config-over-hardcoding: band cutoffs + 800 LOC + 8 files env/config overridable with sensible defaults; no bare magic numbers. | §3.5 (4 env vars) · §3.7.1 (sed-injected cutoffs into agent text) | **Covered** |
| **G3** | No-stub / accurate-claims: scorer derives from real spec content; honest fallback if a dim can't be estimated. | §3.4 (provenance: bash computes math, model estimates from real content) · §5 (edge cases / honest `// 0` + fallback-to-2 instruction) | **Covered** |
| **G4** | Tests: shell tests, negative controls that FAIL on live base (prove-it-first); no green-by-construction tautology. | §4 (Testing Strategy) · §4.2 (prove-it-first red baseline) · §4.3 (anti-tautology note: T7/T8 compute band from raw dims, T12+T13 pair) | **Covered** |
| **G5** | Deploy OUT OF SCOPE for build; branch artifacts + PR-to-fork only. | §6 (Migration/Rollout) | **Covered** |

**No requirement is deferred or unaddressed.** All four functional requirements and all five guardrails are satisfied. The only residual is R2's advisory nature (the score *surfaces* the decomposition obligation but does not hard-block a build) — this is faithful to the PROMPT wording ("MUST PROPOSE", not "MUST block") and is tracked as Risk R5 with a recommended follow-up.

---

## 2. Validation Resolution Log

Each finding from `plans/validation.md` (§5 "Required Fixes" plus the ambiguity/edge-case audits). Every listed fix is incorporated into this spec's §3 implementation instructions.

| ID | Finding (one-line) | Severity | Resolution in this SPEC |
|---|---|---|---|
| **ERROR-1** | Quick-mode "Pi Model Recommendation" is section **5** (line 1750), not 6 — plan's blanket "insert before 6, renumber to 7" is wrong for quick. | High | **Fixed.** §3.7.3 gives per-mode anchors: full/lite insert Complexity Score as **#6**, renumber Pi Model → **#7**; quick inserts as **#5**, renumber Pi Model → **#6**. Explicit per-mode string anchors provided. |
| **DEFECT-2** | T15 asserts substring `12`, but correct output expresses HIGH as `> 11` (MED_MAX default 11) — `12` never appears; the assertion would FAIL against correct code. | Med | **Fixed.** §4.1 T15 now asserts the actually-substituted tokens `≤ 7` (LOW_MAX) and `> 11` (MED_MAX), plus **absence** of raw `__COMPLEXITY_LOW_MAX__`/`__COMPLEXITY_MED_MAX__` placeholders. |
| **GAP-1** | R1 "produced automatically" is instruction-only; no gate requires `## Complexity Score` in SPEC.md; T15 only re-asserts the instruction text (near-tautological). | Med | **Fixed (Option i — the strong fix).** §3.8 adds a `## Complexity Score` header requirement to the SPEC.md entry of `stage_manifest()` so the stage-artifact validator (`validate_stage_artifacts`, line 162) fails a SPEC.md that lacks the block — a real enforceable gate on the produced artifact, directly satisfying "produced automatically". Test T17 added to cover it. |
| **AMB-1** | sed-pipeline continuation not spelled out: existing terminal `__MODE__` line has NO trailing `\`; appending new `| sed` lines without first adding `\` breaks the pipeline. | Med | **Fixed.** §3.7.1 explicitly instructs: append `\` to the existing terminal `__MODE__` sed line, then add the four new sed lines, the LAST of which has NO trailing `\`. |
| **AMB-6** | Threshold env vars are ALSO read via bare `[ -gt ]` directly inside `enrich_complexity`; a non-integer threshold aborts under `set -e` even if helpers are guarded. | Med | **Fixed.** §3.3 routes ALL threshold comparisons through the guarded helpers (or applies the same `case` integer-guard to the env vars inside `enrich_complexity`), and normalizes the thresholds to locals once at the top of `enrich_complexity`. |
| **AMB-2** | Quick mode differs structurally (agent is "Spec Writer", different 5-section list) — one blanket insertion instruction cannot apply by literal match. | Low-Med | **Fixed.** §3.7.3 provides per-mode insertion anchors and notes quick's "Spec Writer" section list (1–5). |
| **AMB-3** | T12/T13/T14 mock scope for `cmd_issue_split` not enumerated; HIGH mock must pin `should_split:false` to avoid the non-interactive `die`. | Low-Med | **Fixed.** §4.1 (T12–T14 rows) + §4.4 enumerate the full mock set (`gh_issue_json`, `safe_repo_main`, `require_cmds`, `analyze_issue_for_split`) and pin HIGH mock to `should_split:false`. |
| **AMB-4** | Top-of-SPEC.md ordering of `## Complexity Score` vs `## Pi Model Recommendation` vs `## 1. …` never stated as one rule. | Low | **Fixed.** §3.7.2 states the canonical order: `## Complexity Score` → `## Pi Model Recommendation` → `## 1. Requirements Traceability Matrix`. |
| **AMB-5** | "≤MED sub-specs" is prose-only; agent has no mechanical ≤MED verification. | Low | **Accepted (documented).** §3.7.2 keeps it as advisory agent-judgment; Risk R5 records that decomposition is advisory not enforced. No code change needed. |
| **Edge: out-of-range dims (dim=9)** | dims not clamped; sum could exceed 15. | Low | **Accepted (honest).** §5 documents values are trusted not validated; an out-of-range dim maps honestly to HIGH — no fabrication, no crash. |
| **Env-var name divergence** | recon suggested `ACORN_COMPLEXITY_LOC_THRESHOLD`; plan uses `ACORN_LOC_DECOMP_THRESHOLD`. | Harmless | **Accepted.** §3.5 uses the plan names (internally consistent; no external contract binds them). Note: this SPEC uses `ACORN_COMPLEXITY_LOW_MAX`/`ACORN_COMPLEXITY_MED_MAX` for band cutoffs (NOT the recon's `_HIGH_THRESHOLD`/`_MED_THRESHOLD`) — see §3.5 rationale. |

**No validation finding is deferred.** All High/Med items are fixed in §3; the three Low items are explicitly accepted with documented justification and (for R5) a follow-up recommendation.

---

## 3. Implementation Plan

### Architecture summary

Two computation sites share one deterministic core:

- **SITE A — manual split path:** `acorn issue split` → `cmd_issue_split()` → `analyze_issue_for_split()` (one `claude` call). The model returns **only raw estimates** (5 dims 1–3, total-LOC, total-files, atomic justification); **bash computes** score/band/size-flag via env thresholds and merges them back (authoritative — overrides any model guess). This is the anti-tautology design: the values under test are computed by our code from raw inputs, never echoed from the model.
- **SITE B — spec-authoring path:** `acorn create` / `acorn issue plan` spawns the tmux Claude pipeline; the **Final Spec agent** writes `SPEC.md`. We instruct that agent (via the `planning_block_*` heredocs, mirroring the existing "Pi Model Recommendation" block) to emit a `## Complexity Score` block, and we enforce its presence via a `stage_manifest` gate.

Both sites share the same rubric prose and the same env cutoffs. Only the deterministic band/size math (§3.2) is single-sourced in bash; the dim-name prose is duplicated as static text across the split prompt and 3 planning blocks (acceptable per the single-file bash architecture; the load-bearing numbers are env-injected, not hardcoded).

### Implementation order (each step independently verifiable)

| Step | What | Depends on | Verify |
|---|---|---|---|
| 1 | §3.5 Env vars (4 declarations) | — | `bash -n bin/acorn` |
| 2 | §3.2 + §3.3 Pure helpers (`complexity_band`, `check_size_thresholds`, `enrich_complexity`) | 1 | T1–T9 |
| 3 | §3.6.1 Extend `analyze_issue_for_split` (prompt + schema + enrich call) | 2 | T10, T11, `test_split.sh` green |
| 4 | §3.6.1b `format_split_recommendation` display | 3 | T12/T13 partial |
| 5 | §3.6.2 `cmd_issue_split` HIGH + size surfacing | 3 | T12, T13, T14 |
| 6 | §3.7 Planning blocks (locals + sed lines + `## Complexity Score` instruction, all 3 modes, per-mode renumber) | 1 | T15 |
| 7 | §3.7.4 Extend `validate_prompt_md` sentinel | 6 | T16, `test_recon_completeness.sh` green |
| 8 | §3.8 `stage_manifest` SPEC.md header gate | — | T17, `test_recon_completeness.sh` / `test_three_artifact.sh` green |
| 9 | §4.5 Full regression suite green; record red→green baseline in `DONE.md` | 1–8 | §4.5 suite |

Step 4 and 5 are order-independent of 6/7/8.

### 3.5 Config — env vars (config-over-hardcoding)

Add at the **top of `bin/acorn`, immediately after `ACORN_OUTPUT_MODE` (line 16)**, following the exact `${VAR:-default}` house pattern:

```bash
# --- Complexity-scoring calibration (decomposition) ---
# Band cutoffs: LOW = score <= LOW_MAX; MED = LOW_MAX < score <= MED_MAX; HIGH = score > MED_MAX.
# 5 dims x 1-3 each => score range 5-15. Defaults: LOW 5-7 . MED 8-11 . HIGH 12-15.
ACORN_COMPLEXITY_LOW_MAX="${ACORN_COMPLEXITY_LOW_MAX:-7}"
ACORN_COMPLEXITY_MED_MAX="${ACORN_COMPLEXITY_MED_MAX:-11}"
# Size gate (independent of band): flag decomposition-review when estimate exceeds either.
ACORN_LOC_DECOMP_THRESHOLD="${ACORN_LOC_DECOMP_THRESHOLD:-800}"
ACORN_FILES_DECOMP_THRESHOLD="${ACORN_FILES_DECOMP_THRESHOLD:-8}"
```

**Naming rationale (resolves the recon divergence):** the band cutoffs are modeled as `LOW_MAX`/`MED_MAX` (upper bounds of each band) rather than the recon's `HIGH_THRESHOLD`/`MED_THRESHOLD`. This makes `complexity_band` a simple two-comparison ladder (`<= LOW_MAX` → LOW, `<= MED_MAX` → MED, else HIGH) with no off-by-one ambiguity at the boundaries. Defaults reproduce the ratified ladder-v4 bands exactly. No external contract binds these names.

No bare magic numbers appear anywhere in the logic body — every cutoff is read from these four vars.

### 3.2 Pure helpers `complexity_band` and `check_size_thresholds`

Place all three new helpers (these two + `enrich_complexity`) **immediately above `analyze_issue_for_split()` (before line 3208)**, so they are defined before use and colocated with decomposition logic. All are pure (no network, no side effects) → deterministic and directly unit-testable. They are the negative-control anchors (undefined on live base → T1–T9 fail before fix).

```bash
# Map a numeric complexity sum (sum of 5 dims) to a band label using configurable
# cutoffs. Non-numeric input OR non-numeric threshold -> honest fallback. Echoes:
# LOW | MED | HIGH | UNKNOWN
complexity_band() {
  local score="$1"
  local low_max="${ACORN_COMPLEXITY_LOW_MAX:-7}"
  local med_max="${ACORN_COMPLEXITY_MED_MAX:-11}"
  case "$score"   in ''|*[!0-9]*) printf 'UNKNOWN'; return 0 ;; esac
  case "$low_max" in ''|*[!0-9]*) low_max=7  ;; esac
  case "$med_max" in ''|*[!0-9]*) med_max=11 ;; esac
  if   [ "$score" -le "$low_max" ]; then printf 'LOW'
  elif [ "$score" -le "$med_max" ]; then printf 'MED'
  else                                   printf 'HIGH'
  fi
}

# Decide whether an estimated size crosses either decomposition-review threshold.
# Independent of the 5-dim band (belt for large-but-not-HIGH specs). Non-numeric
# inputs/thresholds are guarded to integers. Echoes JSON-boolean text: "true" | "false".
check_size_thresholds() {
  local loc="$1" files="$2"
  local loc_thr="${ACORN_LOC_DECOMP_THRESHOLD:-800}"
  local files_thr="${ACORN_FILES_DECOMP_THRESHOLD:-8}"
  case "$loc"       in ''|*[!0-9]*) loc=0       ;; esac
  case "$files"     in ''|*[!0-9]*) files=0     ;; esac
  case "$loc_thr"   in ''|*[!0-9]*) loc_thr=800 ;; esac
  case "$files_thr" in ''|*[!0-9]*) files_thr=8 ;; esac
  if [ "$loc" -gt "$loc_thr" ] || [ "$files" -gt "$files_thr" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}
```

Both helpers integer-guard the **thresholds themselves** (not just the inputs) — closing AMB-6 at the helper level.

### 3.3 Pure helper `enrich_complexity`

Computes authoritative fields from the model's raw estimates and merges them back. **Backward-compat guard first:** if `.complexity.dims` is absent (legacy 3-key JSON), echo the input unchanged. All threshold comparisons inside this function are integer-guarded via normalized locals (closes AMB-6 for the direct comparisons).

```bash
# Given analysis JSON that MAY contain a `.complexity` object with model-supplied
# raw estimates (dims + loc/files totals), compute authoritative score/band/size_flag/
# decomposition_required in BASH (env-threshold driven) and merge them in. If
# `.complexity.dims` is absent, echoes the input unchanged (legacy compatibility).
enrich_complexity() {
  local json="$1"

  # Backward-compat: no complexity block => pass through untouched.
  if ! printf '%s' "$json" | jq -e '.complexity.dims | objects' >/dev/null 2>&1; then
    printf '%s' "$json"; return 0
  fi

  # Normalize thresholds to integer-guarded locals (AMB-6).
  local loc_thr="${ACORN_LOC_DECOMP_THRESHOLD:-800}"
  local files_thr="${ACORN_FILES_DECOMP_THRESHOLD:-8}"
  case "$loc_thr"   in ''|*[!0-9]*) loc_thr=800 ;; esac
  case "$files_thr" in ''|*[!0-9]*) files_thr=8 ;; esac

  local score band loc files review decomp loc_ex files_ex
  score="$(printf '%s' "$json" | jq '
    [ .complexity.dims.files_touched,
      .complexity.dims.loc_estimate,
      .complexity.dims.novelty,
      .complexity.dims.context_depth,
      .complexity.dims.cross_module_fan_out ]
    | map(. // 0) | add')"
  case "$score" in ''|*[!0-9]*) score=0 ;; esac
  band="$(complexity_band "$score")"

  loc="$(printf '%s'   "$json" | jq -r '.complexity.loc_estimate_total   // 0')"
  files="$(printf '%s' "$json" | jq -r '.complexity.files_estimate_total // 0')"
  case "$loc"   in ''|*[!0-9]*) loc=0   ;; esac
  case "$files" in ''|*[!0-9]*) files=0 ;; esac

  review="$(check_size_thresholds "$loc" "$files")"   # "true"/"false"

  decomp=false;   if [ "$band" = "HIGH" ];            then decomp=true;   fi
  loc_ex=false;   if [ "$loc"   -gt "$loc_thr"   ];   then loc_ex=true;   fi
  files_ex=false; if [ "$files" -gt "$files_thr" ];   then files_ex=true; fi

  printf '%s' "$json" | jq \
    --argjson score "$score" \
    --arg     band  "$band" \
    --argjson review "$review" \
    --argjson decomp "$decomp" \
    --argjson loc_ex "$loc_ex" \
    --argjson files_ex "$files_ex" \
    '.complexity.score = $score
     | .complexity.band = $band
     | .complexity.decomposition_required = $decomp
     | .complexity.size_flag = {
         loc_exceeds: $loc_ex,
         files_exceeds: $files_ex,
         decomposition_review_required: $review
       }'
}
```

**`set -e` safety:** every boolean is initialized to `false` then conditionally set via explicit `if…then…fi` (NOT `[ ] && x=true`) — no `-e` abort edge (closes Risk R2). `review`/`decomp`/`loc_ex`/`files_ex` are the literal strings `true`/`false`, consumed by `--argjson` as real JSON booleans.

### 3.4 Data model — extended `analyze_issue_for_split` JSON

**Existing contract (MUST remain intact):**
```json
{ "should_split": true, "reasoning": "...", "sub_issues": [ {"title":"...","scope":"..."} ] }
```

**Extended (additive — new top-level `complexity` object):**
```json
{
  "should_split": true,
  "reasoning": "...",
  "sub_issues": [ {"title":"...","scope":"..."} ],
  "complexity": {
    "dims": {
      "files_touched": 3,
      "loc_estimate": 2,
      "novelty": 3,
      "context_depth": 3,
      "cross_module_fan_out": 2
    },
    "loc_estimate_total": 950,
    "files_estimate_total": 6,
    "atomic_justification": null,

    "score": 13,
    "band": "HIGH",
    "decomposition_required": true,
    "size_flag": {
      "loc_exceeds": true,
      "files_exceeds": false,
      "decomposition_review_required": true
    }
  }
}
```

**Field provenance (no-stub / accurate-claims):**
- `complexity.dims.*`, `loc_estimate_total`, `files_estimate_total`, `atomic_justification` — **provided by the model** (estimated from real issue content).
- `complexity.score`, `band`, `decomposition_required`, `size_flag.*` — **computed by bash** from the model's raw estimates using env thresholds, merged back (authoritative; overrides any model guess).

**Backward compatibility:** the `complexity` object is optional. When the model returns only the 3 legacy keys (as every existing `test_split.sh` mock does), `enrich_complexity()` detects the absence of `.complexity.dims` and returns the JSON unchanged. The structural validator at line 3291 (`has("should_split") and has("reasoning") and has("sub_issues")`) is UNTOUCHED and remains the only structural gate. Nesting under a single `complexity` object keeps legacy keys visually separated and makes the present/absent check a single `jq -e '.complexity.dims'`.

### 3.6 Modify `analyze_issue_for_split()` (lines 3208–3295)

Two surgical edits; the function signature and 3-key contract are unchanged.

#### 3.6.1 Extend the prompt heredoc (lines 3215–3242)

The prompt heredoc is single-quoted (`cat <<'SPLIT_PROMPT_EOF'`, line 3215) → no expansion. Append this prose AFTER the existing "Consider… / should NOT split" guidance and BEFORE the JSON schema block:

```
Additionally, score the implementation COMPLEXITY of this work on five dimensions,
each an integer 1 (trivial), 2 (moderate), or 3 (substantial):
  - files_touched:        how many distinct files/modules must change
  - loc_estimate:         rough lines-of-code magnitude of the change
  - novelty:              how new/unfamiliar the pattern is vs. established code
  - context_depth:        how much surrounding code must be understood first
  - cross_module_fan_out: how many other modules/subsystems are affected
Also give loc_estimate_total (an integer, your best total LOC estimate) and
files_estimate_total (an integer count of files). Estimate ONLY from the real
issue content; do not invent precision. If you cannot estimate a dimension,
use 2 (moderate) and say so in reasoning -- never fabricate.
```

Extend the requested JSON schema block in the prompt to:
```
{
  "should_split": true or false,
  "reasoning": "Brief explanation of your assessment",
  "sub_issues": [ {"title": "...", "scope": "..."} ],
  "complexity": {
    "dims": {
      "files_touched": 1-3, "loc_estimate": 1-3, "novelty": 1-3,
      "context_depth": 1-3, "cross_module_fan_out": 1-3
    },
    "loc_estimate_total": <integer>,
    "files_estimate_total": <integer>,
    "atomic_justification": "<if the work is HIGH complexity but genuinely cannot be split, explain why; otherwise null>"
  }
}
```
Keep the existing trailing guidance ("If should_split is false…", "Aim for 2–5 sub-issues…").

#### 3.6.1a Enrich before validation/print (lines 3288–3294)

Immediately after the raw JSON is parsed and BEFORE the `has(...)` validator, insert the enrichment call. The validator itself is UNCHANGED — it still checks only the three legacy keys, so enrichment can never break it:

```bash
  [ -n "$json" ] || die "Failed to parse split analysis response. Raw output: $response"

  # Compute authoritative complexity score/band/size-flag in bash (env-threshold
  # driven), merging into the model-supplied raw estimates. No-op if the model
  # omitted the complexity block (legacy compatibility).
  json="$(enrich_complexity "$json")"

  # Validate JSON structure using has() to avoid short-circuit on false values
  printf '%s' "$json" | jq -e 'has("should_split") and has("reasoning") and has("sub_issues")' >/dev/null 2>&1 \
    || die "Split analysis returned invalid JSON structure. Got: $json"

  printf '%s' "$json"
```

#### 3.6.1b `format_split_recommendation()` (lines 3299–3331) — additive display

Add a complexity summary, guarded so legacy JSON prints exactly as before (no behavior change when `.complexity.dims` is absent). Insert AFTER the "Reasoning:" echo (line 3311) and BEFORE the `if [ "$should_split" = "true" ]` block (line 3313):

```bash
  # Complexity summary (only when a complexity block is present; legacy-safe).
  if printf '%s' "$json" | jq -e '.complexity.dims | objects' >/dev/null 2>&1; then
    local c_score c_band c_review c_decomp
    c_score="$(printf '%s'  "$json" | jq -r '.complexity.score // "?"')"
    c_band="$(printf '%s'   "$json" | jq -r '.complexity.band  // "?"')"
    c_review="$(printf '%s' "$json" | jq -r '.complexity.size_flag.decomposition_review_required // false')"
    c_decomp="$(printf '%s' "$json" | jq -r '.complexity.decomposition_required // false')"
    echo ""
    echo "Complexity score: ${c_score} (band ${c_band})"
    printf '  dims: files_touched=%s loc_estimate=%s novelty=%s context_depth=%s cross_module_fan_out=%s\n' \
      "$(printf '%s' "$json" | jq -r '.complexity.dims.files_touched')" \
      "$(printf '%s' "$json" | jq -r '.complexity.dims.loc_estimate')" \
      "$(printf '%s' "$json" | jq -r '.complexity.dims.novelty')" \
      "$(printf '%s' "$json" | jq -r '.complexity.dims.context_depth')" \
      "$(printf '%s' "$json" | jq -r '.complexity.dims.cross_module_fan_out')"
    if [ "$c_decomp" = "true" ]; then echo "  ! HIGH band -- decomposition into <=MED sub-specs is REQUIRED unless atomic."; fi
    if [ "$c_review" = "true" ]; then echo "  ! Size threshold exceeded -- decomposition review before build."; fi
  fi
```

#### 3.6.2 `cmd_issue_split()` (lines 3503–3584) — mandatory HIGH surfacing

After the `format_split_recommendation "$analysis" "$issue_number"` call (line 3559) and BEFORE the existing `should_split` extraction/check (line 3563), add a control-flow-preserving surfacing block. This is purely additive stderr output; it does NOT alter the existing `should_split`/`sub_count<2` early-returns:

```bash
  # Decomposition-calibration surfacing (additive; does not change split control flow).
  local c_band c_review
  c_band="$(printf '%s'   "$analysis" | jq -r '.complexity.band // ""')"
  c_review="$(printf '%s' "$analysis" | jq -r '.complexity.size_flag.decomposition_review_required // false')"
  if [ "$c_band" = "HIGH" ]; then
    warn "HIGH complexity (band HIGH) -- MUST PROPOSE decomposition into <=MED sub-specs, or record an atomic justification."
  fi
  if [ "$c_review" = "true" ]; then
    warn "Size estimate exceeds ${ACORN_LOC_DECOMP_THRESHOLD} LOC or ${ACORN_FILES_DECOMP_THRESHOLD} files -- flag: decomposition review before build."
  fi
```

Rationale for `warn` (stderr): these are advisory operator signals; keeping them off stdout means the machine-readable `should_split` flow and any stdout scraping are unaffected. Tests capture stderr via `2>&1`. The exact string `MUST PROPOSE decomposition` is the T12/T13 assertion anchor.

### 3.7 Wire into the spec-authoring path (Requirement 1 core)

The authoring pipeline writes `SPEC.md` via the Final Spec agent (quick mode: "Spec Writer"), whose instructions live in the final-stage prompt inside `planning_block_lite()` (line 1275), `planning_block_full()` (line 1275-region for full; recon: line 771 is another block — use the block that contains the numbered "Pi Model Recommendation" section), and `planning_block_quick()` (line 1581). We inject a new required section into each, mirroring the existing Pi Model Recommendation block.

**Verified section-number anchors (from validation §2/ERROR-1):**
- `planning_block_full`: Pi Model Recommendation is section **6** at line **1235**.
- `planning_block_lite`: Pi Model Recommendation is section **6** at line **1541**.
- `planning_block_quick`: Pi Model Recommendation is section **5** at line **1750** (quick's Spec Writer has only sections 1–5).

#### 3.7.1 New threshold placeholders (config-over-hardcoding inside agent text)

At the TOP of each `planning_block_*` function, resolve the four thresholds into integer-guarded locals (alongside the existing `retry_budget` etc.), exactly matching the existing `retry_budget` treatment:

```bash
  local c_low_max="${ACORN_COMPLEXITY_LOW_MAX:-7}"
  local c_med_max="${ACORN_COMPLEXITY_MED_MAX:-11}"
  local loc_thr="${ACORN_LOC_DECOMP_THRESHOLD:-800}"
  local files_thr="${ACORN_FILES_DECOMP_THRESHOLD:-8}"
  case "$c_low_max" in ''|*[!0-9]*) c_low_max=7  ;; esac
  case "$c_med_max" in ''|*[!0-9]*) c_med_max=11 ;; esac
  case "$loc_thr"   in ''|*[!0-9]*) loc_thr=800  ;; esac
  case "$files_thr" in ''|*[!0-9]*) files_thr=8  ;; esac
```

Then extend each block's sed pipeline. **CRITICAL (AMB-1):** the existing terminal sed line in each block is `| sed "s|__MODE__|${mode}|g"` with NO trailing backslash (verified line 1289 lite; structurally identical in full/quick). You MUST:
1. **Append a `\` to the existing terminal `__MODE__` sed line** so the pipeline continues.
2. Then add the four new sed lines below it, the LAST of which (`__FILES_DECOMP_THRESHOLD__`) has **NO trailing backslash** (it becomes the new pipeline terminus):

```bash
    | sed "s|__MODE__|${mode}|g" \
    | sed "s|__COMPLEXITY_LOW_MAX__|${c_low_max}|g" \
    | sed "s|__COMPLEXITY_MED_MAX__|${c_med_max}|g" \
    | sed "s|__LOC_DECOMP_THRESHOLD__|${loc_thr}|g" \
    | sed "s|__FILES_DECOMP_THRESHOLD__|${files_thr}|g"
```

(Do this in all three blocks. If a given block's terminal sed uses a different last placeholder than `__MODE__`, append the `\` to whatever the current terminal line is, then add the four new lines.)

#### 3.7.2 New required agent section — text (all 3 modes, static prose; cutoffs placeholder-substituted)

Insert this section into each block's final-spec prompt heredoc, per the per-mode anchors in §3.7.3. Canonical top-of-`SPEC.md` ordering the agent must produce (AMB-4): **`## Complexity Score` → `## Pi Model Recommendation` → `## 1. Requirements Traceability Matrix`.**

```
N. **Complexity Score (5-dim)**: Emit a `## Complexity Score` block at the very top of
   SPEC.md (before `## Pi Model Recommendation`). Compute it from the ACTUAL recon + plan
   artifacts (not the raw issue text). Score five dimensions, each an integer 1-3:
   files_touched, LOC_estimate, novelty, context_depth, cross_module_fan_out. Record the
   per-dim values, the SUM, and the band using these cutoffs:
     - LOW  = sum <= __COMPLEXITY_LOW_MAX__
     - MED  = __COMPLEXITY_LOW_MAX__ < sum <= __COMPLEXITY_MED_MAX__
     - HIGH = sum > __COMPLEXITY_MED_MAX__
   Format EXACTLY:
     ## Complexity Score
     score: <sum> (band <LOW|MED|HIGH>)
     dims: files_touched=<n> LOC_estimate=<n> novelty=<n> context_depth=<n> cross_module_fan_out=<n>
     size_estimate: ~<N> LOC, <M> files
     decomposition: <required|not-required>
     atomic_justification: <text, or "n/a">
   RULES:
   - If band is HIGH (sum > __COMPLEXITY_MED_MAX__): decomposition is REQUIRED. Add a
     `## Proposed Decomposition` section listing <=MED sub-specs, UNLESS the work is
     genuinely atomic -- in which case set decomposition: not-required and give a concrete
     atomic_justification (why it cannot be split).
   - Independently of band, if the size estimate exceeds __LOC_DECOMP_THRESHOLD__ LOC OR
     __FILES_DECOMP_THRESHOLD__ files, append a line `size_review: decomposition review
     before build` and note it in the Risk Register.
   - Base every number on the recon/plan artifacts; if a dim cannot be estimated, use 2 and
     state the fallback honestly. Do NOT fabricate precision.
```

`## Complexity Score` uses `## ` so it satisfies the `SPEC.md|^## ` manifest check (§3.8) — no conflict.

#### 3.7.3 Per-mode insertion anchors + renumbering (ERROR-1 / AMB-2 fix)

Apply the §3.7.2 text with `N` set per mode, and renumber the following Pi Model Recommendation section:

| Mode | Function | Anchor: insert immediately BEFORE this literal | New Complexity Score number `N` | Renumber Pi Model Recommendation |
|---|---|---|---|---|
| full | `planning_block_full` | `6. **Pi Model Recommendation**` (line 1235) | **6** | 6 → **7** |
| lite | `planning_block_lite` | `6. **Pi Model Recommendation**` (line 1541) | **6** | 6 → **7** |
| quick | `planning_block_quick` | `5. **Pi Model Recommendation**` (line 1750) | **5** | 5 → **6** |

Only the Pi Model Recommendation heading number changes; do not renumber any other sections. In quick mode the agent is the "Spec Writer" with sections 1–5 — insert as #5 and bump Pi Model to #6. Verify per-mode with T15.

#### 3.7.4 Extend `validate_prompt_md()` sentinel (line 1893)

The sentinel (def line 1886, grep line 1893) rejects a PROMPT.md still containing any unsubstituted `__…__` token. Add the four new placeholders so a future un-substituted leak is caught:

```bash
  if grep -E -q '__SPEC_PATH__|__RETRY_BUDGET__|__RETRY_BACKOFF__|__EVENT_PATH_DISPLAY__|__MODE__|__COMPLEXITY_LOW_MAX__|__COMPLEXITY_MED_MAX__|__LOC_DECOMP_THRESHOLD__|__FILES_DECOMP_THRESHOLD__' "$prompt_path"; then
    return 1
  fi
```

Because the sed pipelines substitute all four, a correctly-rendered PROMPT.md contains none of them and the sentinel passes; `test_recon_completeness.sh` continues to pass. Verify with T16.

### 3.8 `stage_manifest` SPEC.md header gate (GAP-1 fix — enforces R1 "produced automatically")

`stage_manifest()` (line 125) maps mode+stage to expected artifacts; `validate_stage_artifacts()` (line 162) validates each `PATH|^HEADER` entry by grepping the artifact for the header (any-line match, `grep -E -q`). The live base already requires `SPEC.md|^## ` for the final stage of each mode. **Strengthen the SPEC.md entry to ALSO require the `## Complexity Score` heading**, so a produced SPEC.md lacking the score block FAILS the stage gate — a real, enforceable guarantee that the authoring path emitted the score.

Implementation: in `stage_manifest()`, for the final-stage SPEC.md entry of each mode (the entries currently keyed like `SPEC.md|^## `), add a second manifest line requiring the specific header, e.g. append an entry `SPEC.md|^## Complexity Score` to the same stage's manifest list. Concretely, wherever the final stage emits its `SPEC.md|^## ` requirement, add alongside it:

```
SPEC.md|^## Complexity Score
```

so `validate_stage_artifacts` checks BOTH that SPEC.md has some `## ` header AND that it specifically contains a `## Complexity Score` line. Follow the exact existing manifest-entry format (pipe-delimited `path|^header`, one per line in the heredoc/array that `stage_manifest` returns for that mode+stage). Do this for the final stage of **all three modes** (full final stage, lite stage 3, quick final stage) — matching wherever the current `SPEC.md` requirement lives per mode.

**Verification:** T17 (§4.1) drives `validate_stage_artifacts` against (a) a SPEC.md WITH `## Complexity Score` → rc 0, and (b) a SPEC.md WITHOUT it → rc 1. This is a genuine gate on the produced artifact, not a re-assertion of instruction text. `test_recon_completeness.sh` and `test_three_artifact.sh` must remain green (they build SPEC.md fixtures — see §4.5 note: those fixtures may need a `## Complexity Score` line added if they assert the final SPEC.md stage passes; check and update fixtures if required).

#### 3.8a Why not `meta.json`?

`write_meta_json()` (line 2180) runs at `cmd_create` time — BEFORE recon/plan exist — so it cannot hold the high-fidelity authoring-time score (which the agent computes from recon). The requirement is satisfied by the SPEC header block, an option the PROMPT explicitly allows ("SPEC header (or spec meta)"). Leaving `write_meta_json` untouched is the minimal-surgery choice.

---

## 4. Testing Strategy

New file: **`test/test_complexity_score.sh`**, following the exact harness from `test/test_split.sh` and `conventions.md` §Test Framework:

- Header: `#!/usr/bin/env bash` + `set -euo pipefail`.
- `SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"; ACORN_SCRIPT="$SCRIPT_DIR/bin/acorn"`.
- Source functions without running main: `eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"`.
- Copy the `pass`/`fail`/`assert_eq`/`assert_contains`/`assert_not_contains` boilerplate verbatim (conventions §"Standard test harness boilerplate").
- Mock external commands (`claude`, `gh_issue_json`, `safe_repo_main`, `require_cmds`, `analyze_issue_for_split`) via bash function override + `export -f`; `unset -f` in teardown.
- `mktemp -d` setup / `rm -rf` teardown (or `trap … EXIT`).
- Mandatory footer: `printf '\n\033[1mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ] || exit 1`.

### 4.1 Test matrix (each maps to a requirement + is a genuine negative control on live base)

| # | Test | Asserts | Maps to | Fails on live base because |
|---|---|---|---|---|
| T1 | `complexity_band` boundaries | `5→LOW`, `7→LOW`, `8→MED`, `11→MED`, `12→HIGH`, `15→HIGH` | R1 | function undefined |
| T2 | `complexity_band` config override | `ACORN_COMPLEXITY_LOW_MAX=3 ACORN_COMPLEXITY_MED_MAX=6`: `4→MED`, `7→HIGH` | R1,G2 | function undefined |
| T3 | `complexity_band` non-numeric | `complexity_band foo → UNKNOWN` | G3 | function undefined |
| T4 | `check_size_thresholds` LOC gate | `800 0 → false`, `801 0 → true` | R3 | function undefined |
| T5 | `check_size_thresholds` files gate | `0 8 → false`, `0 9 → true` | R3 | function undefined |
| T6 | `check_size_thresholds` config override | `ACORN_LOC_DECOMP_THRESHOLD=100`: `101 0 → true` | R3,G2 | function undefined |
| T7 | `enrich_complexity` computes band | JSON dims summing to 13 → `.complexity.band=="HIGH"`, `.complexity.score==13`, `.decomposition_required==true` | R1 | function undefined |
| T8 | `enrich_complexity` size flag independent of band | dims sum 6 (LOW) + `loc_estimate_total=950` → `.size_flag.decomposition_review_required==true` AND `.decomposition_required==false` (**proves size gate band-independence — R3**) | R3 | function undefined |
| T9 | `enrich_complexity` legacy pass-through | legacy 3-key JSON (no `.complexity`) → output byte-identical, no `.complexity` key added | R4 | function undefined |
| T10 | `analyze_issue_for_split` extended | mock `claude` returns dims → result has `.complexity.band` AND `has(should_split,reasoning,sub_issues)` | R1,R4 | prompt/enrichment absent → no `.complexity` |
| T11 | `analyze_issue_for_split` backward-compat | mock `claude` returns legacy 3-key → validates 3-key contract, no crash, no `.complexity` (**positive control** guarding the contract) | R4 | passes on live base (this is the contract guard) |
| T12 | `cmd_issue_split` HIGH surfacing | mock `analyze_issue_for_split`→`band:HIGH`,`should_split:false`; capture `2>&1`; contains `MUST PROPOSE decomposition` | R2 | surfacing code absent |
| T13 | `cmd_issue_split` LOW does NOT surface | mock→`band:LOW`; assert output does NOT contain `MUST PROPOSE decomposition` (paired with T12 — see §4.3) | R2,G4 | see §4.3 |
| T14 | `cmd_issue_split` size-review surfacing | mock→`size_flag.decomposition_review_required:true`; contains `decomposition review before build` | R3 | surfacing code absent |
| T15 | planning blocks contain scoring instruction (all 3 modes) | each block's rendered output contains `## Complexity Score` AND `5-dim` (or `five dimensions`) AND substituted cutoffs `≤ 7` and `> 11`, AND contains NO literal `__COMPLEXITY_LOW_MAX__`/`__COMPLEXITY_MED_MAX__` | R1,G2,G4 | instruction + placeholders absent |
| T16 | `validate_prompt_md` sentinel | render a PROMPT.md (lite) via `render_prompt_md`, then `validate_prompt_md` rc 0 AND file has no `__..._THRESHOLD__` tokens | R1 | (regression guard) |
| T17 | `stage_manifest` SPEC.md gate (GAP-1) | build a SPEC.md fixture WITH `## Complexity Score` → `validate_stage_artifacts` final stage rc 0; a fixture WITHOUT it → rc 1 | R1 | manifest header requirement absent on live base (a SPEC.md without the block passes) |

### 4.2 Prove-it-first procedure (per PROMPT guardrail)

Before writing the fix, run the new test file against the **live-base** `bin/acorn`. Expected RED baseline: **T1–T10, T12, T14, T15, T16, T17 FAIL** (undefined functions / missing strings / absent gate); **T11 and T13 pass** (contract still holds / string legitimately absent). Record this baseline in `DONE.md`. Then implement §3; re-run → all green.

### 4.3 Anti-tautology guarantee (gate-test-drives-real-code)

- **T7/T8** feed ONLY raw dims + totals and assert the band/flag our code COMPUTES — the expected band is never present in the input, so the test cannot pass by echoing its fixture.
- **T13's live-base ambiguity:** on the live base the `MUST PROPOSE` string is absent for the trivial reason that the whole feature is absent, so T13 would "pass" vacuously. To make T13 meaningful, assert in the SAME run BOTH that the T12 HIGH-band mock DOES emit the string AND the T13 LOW-band mock does NOT — the pair is only satisfiable by band-conditional code, never by the live base. Implement T12 and T13 as a paired assertion in one test function.
- **T17** is a real artifact gate (drives `validate_stage_artifacts` against a produced SPEC.md), not a re-assertion of the instruction text — this is the strong closure of GAP-1 that the PROMPT's gate-test doctrine demands.

This satisfies the PROMPT's "green-by-construction guard is NOT acceptable" constraint.

### 4.4 `cmd_issue_split` test mock set (AMB-3)

To exercise `cmd_issue_split` in T12/T13/T14, mock the FULL set used by existing `test_split.sh` (lines 179–201): `gh_issue_json` (return valid JSON with a `.comments` array so `render_comments_block` runs cleanly), `safe_repo_main`, `require_cmds` (no-op), and `analyze_issue_for_split` (return the fixture JSON with the desired `.complexity.band` / `size_flag`). **Pin the HIGH-band mock to `should_split:false`** so control flow hits the early `return 0` after the `warn` — otherwise `cmd_issue_split` reaches the non-interactive `die` (line 3584) or needs `--yes` + a `create_sub_issues` mock. This keeps the tests simple and deterministic. Invoke via a subshell `( cmd_issue_split … 2>&1 )` to capture stderr and avoid aborting the outer shell.

### 4.5 Regression suite (must stay green)

Run after implementation:
```bash
bash -n bin/acorn                      # parseable (quality gate, cf. test_rt_gate_removal.sh)
bash test/test_split.sh                # existing split contract + all tests (exercises enrich_complexity pass-through)
bash test/test_recon_completeness.sh   # validate_prompt_md / stage manifest
bash test/test_three_artifact.sh       # render_prompt_md three-artifact path
bash test/test_complexity_score.sh     # NEW
```
`test_split.sh` mocks `claude` returning legacy 3-key JSON → exercises the `enrich_complexity` pass-through path → MUST remain fully green (the real backward-compat proof).

**Fixture caveat (§3.8 interaction):** `test_recon_completeness.sh` / `test_three_artifact.sh` may build SPEC.md fixtures and assert the final-stage gate passes. After adding the `SPEC.md|^## Complexity Score` manifest requirement, any such fixture that asserts a PASS on the final SPEC.md stage must include a `## Complexity Score` line. Check both test files; if they assert final-stage SPEC.md validation, add the header line to their fixtures. If they only exercise earlier stages (recon/plan), no change is needed.

**Out of scope (do not run/modify):** `test_planning_block_clarify.sh`, `test_auto_trigger_clarify_hint.sh` — pre-existing failures from the backed-out clarify feature; PROMPT forbids touching clarify code.

---

## 5. Edge Cases & Error Handling

| Case | Handling |
|---|---|
| Model omits `complexity` block (legacy mock / non-compliance) | `enrich_complexity` guard returns JSON unchanged; validator still passes on 3 keys; display/surface guards see no `.complexity.dims` and print nothing. No crash, full backward compat. |
| Dims present but null / out-of-range | `jq map(. // 0) | add` coerces null→0; out-of-range (e.g. 9) is NOT clamped — sum maps honestly to HIGH (accepted, no fabrication). Values are trusted, not validated. |
| `loc_estimate_total`/`files_estimate_total` missing/non-numeric | `jq '… // 0'` + `case` integer-guard → 0 → size gate simply doesn't fire. |
| Non-integer threshold env var | Integer-`case`-guarded inside `complexity_band`, `check_size_thresholds`, AND `enrich_complexity` (§3.2/§3.3, closes AMB-6) → falls back to default, never aborts under `set -e`. |
| `claude` CLI fails / unauth | Existing `die` path (lines 3258–3263) fires before enrichment. Unchanged. |
| `jq` malformed JSON | Existing parse `die` (line 3288) fires before enrichment. Unchanged. |
| HIGH band but <2 sub_issues in split path | `warn` emitted before the existing early-return; advisory both ways — operator is told to decompose even though the split flow declines. Intentional (§3.6.2). |
| `## Complexity Score` vs SPEC manifest | `## ` heading satisfies `SPEC.md|^## `; §3.8 adds a specific requirement for it. No collision. |
| Unsubstituted placeholder leaks to PROMPT.md | `validate_prompt_md` sentinel (§3.7.4) catches it → validation fails loudly. |
| `set -e` on boolean assignment | Explicit `if…then…fi` form everywhere (§3.3); no `[ ] && x=` idiom. |

**Fail-loud vs. degrade:** the manual-split `claude` path keeps its existing fail-loud `die`. The complexity *enrichment* degrades gracefully (pass-through) because a missing complexity block must never break the legacy contract. Contract preservation > new-feature completeness on the additive path.

**Security:** no new surface. Model JSON flows through `jq` only (no `eval` of model fields). Threshold env vars are integer-guarded (no injection into arithmetic). sed substitutes only guarded integers into instruction text (no shell-metachar path). `--argjson` receives only literal `true`/`false`/computed integers.

---

## 6. Risk Register & Migration

### Risk register (unresolved / residual risks)

| ID | Risk | Sev | Likelihood | Mitigation |
|---|---|---|---|---|
| R1 | Model non-compliance: malformed/partial `complexity` block | Med | Med | `enrich_complexity` guard + `jq // 0` coercion → pass-through or honest-0; never breaks 3-key contract. T9/T11 lock it. |
| R2 | `set -e` trips on a boolean assignment in `enrich_complexity` | Med | Low | Explicit `if…then…fi` form (§3.3); `bash -n` + T7/T8 catch regressions. |
| R3 | Unsubstituted `__..._THRESHOLD__` leaks into PROMPT.md | Med | Low | All 4 added to `validate_prompt_md` sentinel (§3.7.4); T16 verifies. |
| R4 | Rubric prose drifts between the 4 copies (split prompt + 3 planning blocks) | Low | Med | Thresholds single-sourced from env (sed-injected); only static dim-name prose duplicated. Keep-in-sync code comment. Acceptable per single-file bash constraint. |
| R5 | Score is advisory — a HIGH spec can still proceed to build without decomposing (authoring path) | Low | Med | **By design** (PROMPT says "MUST PROPOSE", not "MUST block"). §3.8 gate enforces the score is EMITTED, but not that decomposition happened. **Follow-up (deferred):** a future gate could parse `decomposition: required` + absence of `## Proposed Decomposition` and hard-fail; out of scope here. |
| R6 | Authoring-time score is model-judgment (not deterministic) unlike the bash split-path math | Low | High | Accepted: SPEC-time score is inherently judgment from recon/plan; the deterministic core governs the machine-readable split path. §3.7.2 pins exact cutoffs + format to reduce variance; §3.8 gate ensures presence. |
| R7 | Existing `test_split.sh` breaks due to enrichment | High | Low | Enrichment is a strict no-op when `.complexity.dims` absent (every legacy mock). Run `test_split.sh` in step 3. |
| R8 | `jq --argjson` rejects a non-`true`/`false` string | Med | Low | `check_size_thresholds` echoes exactly `true`/`false`; T4–T6 pin the literal output. |
| R9 | §3.8 manifest gate breaks `test_recon_completeness.sh`/`test_three_artifact.sh` fixtures | Med | Med | §4.5 fixture caveat: audit both tests; add `## Complexity Score` to any fixture that asserts final-stage SPEC.md PASS. Verify green in step 8. |

### Migration / rollout

- **No data migration** — no DB, no persisted state; the artifact is the single bash file.
- **No breaking change** — every edit is additive; legacy JSON, legacy tests, and existing PROMPT.md structure preserved. A downstream caller ignoring `.complexity` sees identical behavior.
- **Deploy OUT OF SCOPE for this build** (per PROMPT G5). Build produces branch artifacts + PR-to-fork only. Deploy to `~/acorn/bin` and `~/.foreman/bin` is a separate post-per-merge step with backup (builder-no-pre-gate-live).
- **Rollback** — revert the single commit; changes are additive and namespaced under `.complexity` / new functions / new env vars → clean revert, zero residual state.
- **Config rollout** — defaults reproduce ladder-v4 bands (LOW 5–7 / MED 8–11 / HIGH 12–15) and size gate (800 LOC / 8 files). Operators retune via env, no code change.

### Completion protocol (per PROMPT.md)

On completion, the implementing agent writes `DONE.md` in the spec directory (`.specs/3-decomposition-calibration-5-dim-complexity-score-a/DONE.md`, NOT the worktree root) including: the exact test commands run (§4.5) and their outcomes; the RED→GREEN prove-it-first baseline (§4.2); a `## Work Type` section (category: build/code; primary artifacts: `bin/acorn`, `test/test_complexity_score.sh`); concise file-change bullets; and any follow-up risks (notably R5 advisory-not-enforced, R9 fixture audit).
