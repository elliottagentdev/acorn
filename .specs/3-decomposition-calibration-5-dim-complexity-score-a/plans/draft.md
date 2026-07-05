# Implementation Plan — Decomposition-Calibration: 5-Dim Complexity Score

**Repo:** `elliottagentdev/acorn` (our fork)
**Build base branch (mandatory):** `forge-acorn-live-base` @ `d83a162` (byte-exact live-deployed acorn)
**Scope:** Calibrate decomposition logic only. No unrelated refactors. Do NOT touch pre-Stage-0 `/clarify` code.

---

## 1. Executive Summary

Add a deterministic, config-driven **5-dimension complexity score** to acorn that is:

1. **Surfaced at spec-authoring time** — the Final Spec agent computes and records a `## Complexity Score` block in `SPEC.md` on every run of the `acorn create` / `acorn issue plan` pipeline (all three modes).
2. **Enforced on HIGH (≥12)** — a HIGH band forces a decomposition proposal into ≤MED sub-specs, unless the spec is genuinely atomic (with a recorded justification).
3. **Belt-and-braces on size** — an independent size gate flags "decomposition review before build" when the estimate exceeds ~800 LOC OR >8 files, regardless of band.
4. **Additive to the manual path** — `acorn issue split` keeps working. `analyze_issue_for_split()` gains complexity fields in its JSON *without* breaking the existing `should_split`/`reasoning`/`sub_issues` contract or any current consumer/test.

### Design center of gravity: deterministic bash core + LLM estimates

The **numeric mapping is done in bash** (authoritative, testable, config-driven); the **LLM only provides raw estimates** (the five 1–3 dim values, a total-LOC estimate, a total-files estimate, and an atomic justification). Bash then computes score = Σdims, maps score→band via env thresholds, computes the size flag via env thresholds, and merges those authoritative values back into the JSON — *overriding* any band/flag the model guessed. This is the key robustness + anti-tautology decision: the thing under test (band/flag computation) is computed by our code from raw inputs, never echoed from the model's own output.

### Files touched

| File | Change | Type |
|---|---|---|
| `bin/acorn` | 4 env-var defaults; 3 new pure-bash helpers; extend `analyze_issue_for_split`; extend `format_split_recommendation`; surface in `cmd_issue_split`; inject scoring instructions + 4 threshold placeholders into 3 `planning_block_*`; extend `validate_prompt_md` sentinel | Modify |
| `test/test_complexity_score.sh` | New shell test with negative controls (prove-it-first) | Create |

No other files. No new runtime dependencies. No build step.

---

## 2. Architecture & Data Flow

There are **two computation sites** for the score, both using the *same* rubric and the *same* env thresholds:

```
                          ┌─────────────────────────────────────────────┐
                          │  SHARED DETERMINISTIC CORE (pure bash)       │
                          │  - complexity_band(score)                    │
                          │  - check_size_thresholds(loc, files)         │
                          │  - env thresholds ACORN_COMPLEXITY_*         │
                          └─────────────────────────────────────────────┘
                                   ▲                         ▲
         ┌─────────────────────────┘                         └───────────────────────┐
         │ SITE A: manual split path                          SITE B: authoring path  │
         │                                                                            │
  acorn issue split                                        acorn create / issue plan  │
    → cmd_issue_split()                                      → cmd_create()           │
      → analyze_issue_for_split()  (claude one-shot)           → render_prompt_md()   │
        → prompt asks for dims+LOC+files+justification            → planning_block()  │
        → enrich_complexity() computes score/band/flag              (lite/full/quick) │
        → JSON gains .complexity.*                                → Final Spec agent  │
      → format_split_recommendation() shows score                   reads instructions│
      → HIGH ⇒ print MUST-PROPOSE-DECOMPOSITION surfacing            computes 5-dim,   │
      → size-flag ⇒ print decomposition-review surfacing             records          │
                                                                     ## Complexity     │
                                                                     Score block in    │
                                                                     SPEC.md           │
```

**Why two sites, not one shared claude call?** acorn's authoring pipeline is fundamentally agent-driven: `cmd_create` spawns a tmux Claude Code session that runs the multi-stage pipeline and *the Final Spec agent* is what actually writes `SPEC.md`. The natural, minimal-surgery way to "produce the score automatically at spec-authoring time" (Requirement 1) is to instruct that agent via the `planning_block_*` heredocs — mirroring exactly how the existing "Pi Model Recommendation" section is produced. Adding a separate pre-recon claude call in `cmd_create` would (a) duplicate a network call, (b) score from issue-text-only before recon exists (lower fidelity), and (c) touch the hot create path unnecessarily. The manual `split` path already makes a claude call (`analyze_issue_for_split`), so we extend that one rather than add another.

Both sites share the **deterministic band/size math** so the env thresholds are authoritative in both. The rubric *prose* (5 dim names, 1–3 scale, band table) is duplicated as static text across the split prompt and the 3 planning blocks — acceptable given the single-file bash architecture and the additive constraint; the load-bearing numbers (cutoffs/thresholds) are injected from the env vars, not hardcoded.

---

## 3. Configuration (config-over-hardcoding)

Add these four declarations at the **top of `bin/acorn`**, immediately after `ACORN_OUTPUT_MODE` (line 16), following the exact `${VAR:-default}` house pattern:

```bash
# --- Complexity-scoring calibration (decomposition) ---
# Band cutoffs: LOW = score ≤ LOW_MAX; MED = LOW_MAX < score ≤ MED_MAX; HIGH = score > MED_MAX.
# 5 dims × 1–3 each ⇒ score range 5–15. Defaults: LOW 5–7 · MED 8–11 · HIGH 12–15.
ACORN_COMPLEXITY_LOW_MAX="${ACORN_COMPLEXITY_LOW_MAX:-7}"
ACORN_COMPLEXITY_MED_MAX="${ACORN_COMPLEXITY_MED_MAX:-11}"
# Size gate (independent of band): flag decomposition-review when estimate exceeds either.
ACORN_LOC_DECOMP_THRESHOLD="${ACORN_LOC_DECOMP_THRESHOLD:-800}"
ACORN_FILES_DECOMP_THRESHOLD="${ACORN_FILES_DECOMP_THRESHOLD:-8}"
```

No bare magic numbers appear anywhere in the logic body — every cutoff is read from these vars, and the threshold values injected into the agent instructions come from these vars via sed substitution (§7).

---

## 4. Data Model — Extended `analyze_issue_for_split` JSON

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

**Field provenance (critical for no-stub / accurate-claims):**
- `complexity.dims.*`, `loc_estimate_total`, `files_estimate_total`, `atomic_justification` — **provided by the model** (estimated from real issue content).
- `complexity.score`, `band`, `decomposition_required`, `size_flag.*` — **computed by bash** from the model's raw estimates using env thresholds, and merged back (authoritative; overrides any model guess).

**Backward compatibility:** the `complexity` object is optional. When the model returns only the 3 legacy keys (as every existing `test_split.sh` mock does), `enrich_complexity()` detects the absence of `.complexity.dims` and returns the JSON unchanged. The `jq -e 'has("should_split") and has("reasoning") and has("sub_issues")'` validator at line 3291 is untouched and still the only structural gate.

**Nesting rationale:** a single `complexity` object (vs. flat fields) keeps the legacy contract keys visually separated, makes the "present/absent" backward-compat check a single `jq -e '.complexity.dims'`, and avoids any name collision with existing keys.

---

## 5. New Pure-Bash Helpers (in `bin/acorn`)

Place these three helpers immediately **above** `analyze_issue_for_split()` (before line 3208), so they are defined before use and sit with the other decomposition logic. All three are pure (no network, no side effects) → directly unit-testable and deterministic. They are the *only* place the band/size math lives, and they are the negative-control anchors (undefined on live base → tests fail before fix).

### 5.1 `complexity_band()`

```bash
# Map a numeric complexity sum (Σ of 5 dims) to a band label using configurable
# cutoffs. Non-numeric input → "UNKNOWN" (honest fallback, never a silent 0-band).
# Echoes: LOW | MED | HIGH | UNKNOWN
complexity_band() {
  local score="$1"
  case "$score" in ''|*[!0-9]*) printf 'UNKNOWN'; return 0 ;; esac
  if   [ "$score" -le "$ACORN_COMPLEXITY_LOW_MAX" ]; then printf 'LOW'
  elif [ "$score" -le "$ACORN_COMPLEXITY_MED_MAX" ]; then printf 'MED'
  else                                                    printf 'HIGH'
  fi
}
```

### 5.2 `check_size_thresholds()`

```bash
# Decide whether an estimated size crosses either decomposition-review threshold.
# Independent of the 5-dim band (belt for large-but-not-HIGH specs). Non-numeric
# inputs are treated as 0 (never crosses). Echoes JSON-boolean text: "true" | "false".
check_size_thresholds() {
  local loc="$1" files="$2"
  case "$loc"   in ''|*[!0-9]*) loc=0   ;; esac
  case "$files" in ''|*[!0-9]*) files=0 ;; esac
  if [ "$loc" -gt "$ACORN_LOC_DECOMP_THRESHOLD" ] || [ "$files" -gt "$ACORN_FILES_DECOMP_THRESHOLD" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}
```

### 5.3 `enrich_complexity()`

Computes the authoritative fields from the model-supplied raw estimates and merges them back. **Backward-compat guard first**: if `.complexity.dims` is absent (legacy 3-key JSON), return input unchanged.

```bash
# Given analysis JSON that MAY contain a `.complexity` object with model-supplied
# raw estimates (dims + loc/files totals), compute the authoritative score/band/
# size_flag/decomposition_required in BASH (env-threshold driven) and merge them in.
# If `.complexity.dims` is absent, echoes the input unchanged (legacy compatibility).
enrich_complexity() {
  local json="$1"

  # Backward-compat: no complexity block ⇒ pass through untouched.
  if ! printf '%s' "$json" | jq -e '.complexity.dims | objects' >/dev/null 2>&1; then
    printf '%s' "$json"; return 0
  fi

  local score band loc files review decomp loc_ex files_ex
  score="$(printf '%s' "$json" | jq '
    [ .complexity.dims.files_touched,
      .complexity.dims.loc_estimate,
      .complexity.dims.novelty,
      .complexity.dims.context_depth,
      .complexity.dims.cross_module_fan_out ]
    | map(. // 0) | add')"
  band="$(complexity_band "$score")"

  loc="$(printf '%s'  "$json" | jq -r '.complexity.loc_estimate_total   // 0')"
  files="$(printf '%s' "$json" | jq -r '.complexity.files_estimate_total // 0')"
  case "$loc"   in ''|*[!0-9]*) loc=0   ;; esac
  case "$files" in ''|*[!0-9]*) files=0 ;; esac

  review="$(check_size_thresholds "$loc" "$files")"        # "true"/"false"
  decomp=false;  [ "$band" = "HIGH" ] && decomp=true
  loc_ex=false;  [ "$loc"   -gt "$ACORN_LOC_DECOMP_THRESHOLD"   ] && loc_ex=true
  files_ex=false;[ "$files" -gt "$ACORN_FILES_DECOMP_THRESHOLD" ] && files_ex=true

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

Notes:
- `review`/`decomp`/`loc_ex`/`files_ex` are the literal strings `true`/`false`, consumed by `--argjson` as real JSON booleans.
- Under `set -euo pipefail`, the `[ ... ] && x=true` idiom is safe because the `x=false` default precedes it and the compound is the final statement of each line (a false test yields the default, not a script abort — the `&&` short-circuits to the assignment, and a failing `[ ]` on the RHS of `&&` returns non-zero only for that compound which is not the last command in a `&&`/`||` chain that would trip `-e`). To be defense-in-depth explicit and avoid any `-e` edge, implement each as:
  ```bash
  if [ "$loc" -gt "$ACORN_LOC_DECOMP_THRESHOLD" ]; then loc_ex=true; fi
  ```
  **Use the explicit `if` form in the real code** (clearer control flow / DX, no `-e` ambiguity).

---

## 6. Modify `analyze_issue_for_split()` (lines 3208–3295)

Two surgical edits; the function signature and 3-key contract are unchanged.

### 6.1 Extend the prompt heredoc (lines 3215–3242)

Append a complexity-scoring block to the `SPLIT_PROMPT_EOF` heredoc, *before* the JSON schema, and add the `complexity` object to the requested JSON. The heredoc is single-quoted (`<<'SPLIT_PROMPT_EOF'`) so no expansion — the 1–3 scale and band table are static prose; the model returns only raw estimates, bash owns the cutoffs.

New prose to insert after the existing "Consider… / should NOT split" guidance:

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
use 2 (moderate) and say so in reasoning — never fabricate.
```

Extend the JSON schema block in the prompt to:
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

### 6.2 Enrich before validation/print (line 3288–3294)

Immediately after the raw JSON is parsed and *before* the `has(...)` validator, insert the enrichment call:

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

The validator is unchanged — it still checks only the three legacy keys, so enrichment can never break it.

---

## 7. Surface in the Manual Split Path

### 7.1 `format_split_recommendation()` (lines 3299–3331) — additive display

Add a complexity summary, guarded so legacy JSON prints exactly as before (no behavior change when `.complexity.dims` is absent). Insert after the "Reasoning:" line, before the `if [ "$should_split" = "true" ]` block:

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
    [ "$c_decomp" = "true" ] && echo "  ⚠ HIGH band — decomposition into ≤MED sub-specs is REQUIRED unless atomic."
    [ "$c_review" = "true" ] && echo "  ⚠ Size threshold exceeded — decomposition review before build."
  fi
```

### 7.2 `cmd_issue_split()` (lines 3554–3579) — mandatory HIGH surfacing

After `format_split_recommendation "$analysis" "$issue_number"` (line 3559) and *before* the existing `should_split` check, add an explicit, control-flow-preserving surfacing block. This is purely additive output; it does **not** alter the existing `should_split`/`sub_count<2` early-returns (backward compat).

```bash
  # Decomposition-calibration surfacing (additive; does not change split control flow).
  local c_band c_review
  c_band="$(printf '%s'   "$analysis" | jq -r '.complexity.band // ""')"
  c_review="$(printf '%s' "$analysis" | jq -r '.complexity.size_flag.decomposition_review_required // false')"
  if [ "$c_band" = "HIGH" ]; then
    warn "HIGH complexity (band HIGH) — MUST PROPOSE decomposition into ≤MED sub-specs, or record an atomic justification."
  fi
  if [ "$c_review" = "true" ]; then
    warn "Size estimate exceeds ${ACORN_LOC_DECOMP_THRESHOLD} LOC or ${ACORN_FILES_DECOMP_THRESHOLD} files — flag: decomposition review before build."
  fi
```

Rationale for `warn` (stderr): these are advisory signals to the operator; keeping them off stdout means the machine-readable `should_split` flow and any stdout scraping are unaffected. Tests capture stderr via `2>&1`.

---

## 8. Wire Into the Spec-Authoring Path (Requirement 1 core)

The authoring pipeline writes `SPEC.md` via the **Final Spec agent**, whose instructions live in the Stage-3 (`lite`/`quick`) or Stage-5 (`full`) prompt inside `planning_block_lite()` / `planning_block_full()` / `planning_block_quick()`. We inject a new required section into each, mirroring the existing "Pi Model Recommendation" block (lines 1541–1550 in lite; equivalent in full/quick).

### 8.1 New threshold placeholders (config-over-hardcoding inside agent text)

Add four sed substitutions to **each** of the three planning blocks' sed pipelines (lite pipeline shown at lines 1284–1289). New lines to append to each pipeline:

```bash
    | sed "s|__COMPLEXITY_LOW_MAX__|${ACORN_COMPLEXITY_LOW_MAX}|g" \
    | sed "s|__COMPLEXITY_MED_MAX__|${ACORN_COMPLEXITY_MED_MAX}|g" \
    | sed "s|__LOC_DECOMP_THRESHOLD__|${ACORN_LOC_DECOMP_THRESHOLD}|g" \
    | sed "s|__FILES_DECOMP_THRESHOLD__|${ACORN_FILES_DECOMP_THRESHOLD}|g"
```

And at the top of each `planning_block_*` function, resolve the values into locals (alongside the existing `retry_budget` etc.), so the sed reads a validated integer:

```bash
  local c_low_max="${ACORN_COMPLEXITY_LOW_MAX:-7}"
  local c_med_max="${ACORN_COMPLEXITY_MED_MAX:-11}"
  local loc_thr="${ACORN_LOC_DECOMP_THRESHOLD:-800}"
  local files_thr="${ACORN_FILES_DECOMP_THRESHOLD:-8}"
  case "$c_low_max" in ''|*[!0-9]*) c_low_max=7 ;; esac
  case "$c_med_max" in ''|*[!0-9]*) c_med_max=11 ;; esac
  case "$loc_thr"   in ''|*[!0-9]*) loc_thr=800 ;; esac
  case "$files_thr" in ''|*[!0-9]*) files_thr=8 ;; esac
```
(and reference `${c_low_max}` etc. in the sed lines instead of the raw env var, matching the existing `retry_budget` treatment).

### 8.2 New required agent section (inserted into the Final Spec prompt heredoc, all 3 modes)

Insert a numbered section immediately before "6. **Pi Model Recommendation**" (renumber Pi Model Recommendation to 7). Text (static prose; cutoffs are placeholder-substituted):

```
6. **Complexity Score (5-dim)**: Emit a `## Complexity Score` block at the very top of
   SPEC.md (before `## Pi Model Recommendation`). Compute it from the ACTUAL recon + plan
   artifacts (not the raw issue text). Score five dimensions, each an integer 1–3:
   files_touched, LOC_estimate, novelty, context_depth, cross_module_fan_out. Record the
   per-dim values, the SUM, and the band using these cutoffs:
     - LOW  = sum ≤ __COMPLEXITY_LOW_MAX__
     - MED  = __COMPLEXITY_LOW_MAX__ < sum ≤ __COMPLEXITY_MED_MAX__
     - HIGH = sum > __COMPLEXITY_MED_MAX__
   Format exactly:
     ## Complexity Score
     score: <sum> (band <LOW|MED|HIGH>)
     dims: files_touched=<n> LOC_estimate=<n> novelty=<n> context_depth=<n> cross_module_fan_out=<n>
     size_estimate: ~<N> LOC, <M> files
     decomposition: <required|not-required>
     atomic_justification: <text, or "n/a">
   RULES:
   - If band is HIGH (sum > __COMPLEXITY_MED_MAX__): decomposition is REQUIRED. Add a
     `## Proposed Decomposition` section listing ≤MED sub-specs, UNLESS the work is
     genuinely atomic — in which case set decomposition: not-required and give a concrete
     atomic_justification (why it cannot be split).
   - Independently of band, if the size estimate exceeds __LOC_DECOMP_THRESHOLD__ LOC OR
     __FILES_DECOMP_THRESHOLD__ files, append a line `size_review: decomposition review
     before build` and note it in the Risk Register.
   - Base every number on the recon/plan artifacts; if a dim cannot be estimated, use 2 and
     state the fallback honestly. Do NOT fabricate precision.
```

The `## Complexity Score` heading uses `## ` so it satisfies the `SPEC.md|^## ` manifest check (`stage_manifest`, line 125) — no conflict.

### 8.3 Update `validate_prompt_md()` sentinel (line ~1892)

The sentinel rejects a PROMPT.md that still contains any unsubstituted `__...__` token. Add the four new placeholders to its regex so a future un-substituted leak is caught:

```bash
  if grep -E -q '__SPEC_PATH__|__RETRY_BUDGET__|__RETRY_BACKOFF__|__EVENT_PATH_DISPLAY__|__MODE__|__COMPLEXITY_LOW_MAX__|__COMPLEXITY_MED_MAX__|__LOC_DECOMP_THRESHOLD__|__FILES_DECOMP_THRESHOLD__' "$prompt_path"; then
    return 1
  fi
```

Because the sed pipelines substitute all four, a correctly-rendered PROMPT.md contains none of them and the sentinel passes. `test_recon_completeness.sh` (which exercises `validate_prompt_md`) continues to pass.

### 8.4 Why not store the score in `meta.json`?

`write_meta_json()` (line ~2180) runs at `cmd_create` time — *before* recon/plan exist — so it cannot hold the high-fidelity authoring-time score (which the agent computes from recon). The requirement is satisfied by recording it in the **SPEC header** (`## Complexity Score` block), the option the requirement explicitly allows ("SPEC header (or spec meta)"). Leaving `write_meta_json` untouched is the minimal-surgery choice and avoids extending the meta contract for a value that would only ever be a low-fidelity placeholder.

---

## 9. Error Handling & Edge Cases

| Case | Handling |
|---|---|
| Model omits `complexity` block entirely (legacy mock, or model non-compliance) | `enrich_complexity` guard returns JSON unchanged; `analyze_issue_for_split` still validates + returns 3-key JSON; `format_split_recommendation`/`cmd_issue_split` guards see no `.complexity.dims` and print nothing extra. **No crash, full backward compat.** |
| Model returns dims but non-integer / out-of-range values | `jq map(. // 0) | add` coerces null→0; sum may be low → band computed honestly from whatever was given (no fabrication). `complexity_band` returns `UNKNOWN` only if the *sum* is non-numeric (shouldn't happen post-`add`). |
| `loc_estimate_total` / `files_estimate_total` missing or non-numeric | `jq '... // 0'` + `case` integer-guard in `enrich_complexity` → treated as 0 → size gate simply doesn't fire. |
| Env threshold set to non-integer (`ACORN_COMPLEXITY_MED_MAX=foo`) | `complexity_band` compares with `[ -le ]` which would error under bad input; **guard**: add `case` integer-guards where the thresholds are consumed, OR (preferred) integer-guard them once at declaration is not possible (they're used across functions), so guard inside `complexity_band`/`check_size_thresholds`: `case "$ACORN_COMPLEXITY_LOW_MAX" in ''|*[!0-9]*) ... ;; esac` fallback to defaults. **Include these guards in the helpers.** |
| `claude` CLI fails / not authenticated | Unchanged existing path: `die` with the existing message (lines 3258–3263). Enrichment never reached. |
| `jq` receives malformed JSON | Unchanged: existing parse/`die` at line 3288 fires before enrichment. |
| HIGH band but model gives no sub_issues | `cmd_issue_split` still honors the existing `should_split`/`sub_count<2` early-return; the HIGH `warn` is emitted regardless (advisory), so the operator is told to decompose even though the split flow declines — intentional and correct (the manual command reports both signals). |
| Score block heading collides with SPEC manifest | `## Complexity Score` is a `## ` heading → satisfies `SPEC.md|^## `; no collision. |
| Unsubstituted placeholder leaks into PROMPT.md | `validate_prompt_md` sentinel (extended in §8.3) catches it → PROMPT.md validation fails loudly. |

**Fail-loud vs. degrade:** the manual-split claude path keeps its existing fail-loud `die`. The complexity *enrichment* degrades gracefully (pass-through) because a missing complexity block must never break the legacy contract. This split is deliberate: contract preservation > new-feature completeness on the additive path.

---

## 10. Testing Strategy

New file: `test/test_complexity_score.sh`, following the exact harness in `test/test_split.sh` / `conventions.md` §Test:
- `eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"` to source functions without running `main`.
- `pass`/`fail`/`assert_eq`/`assert_contains`/`assert_not_contains` helpers (copy boilerplate).
- Mock `claude` via bash function + `export -f` where a claude call is exercised.
- `mktemp -d` setup / teardown with `unset -f`.
- Footer: `printf 'Results…'; [ "$FAIL" -eq 0 ] || exit 1`.

### 10.1 Test matrix (each maps to a requirement + is a genuine negative control on live base)

| # | Test | Asserts | Fails on live base because |
|---|---|---|---|
| T1 | `complexity_band` boundaries | `complexity_band 5→LOW`, `7→LOW`, `8→MED`, `11→MED`, `12→HIGH`, `15→HIGH` | function undefined |
| T2 | `complexity_band` config override | with `ACORN_COMPLEXITY_LOW_MAX=3 ACORN_COMPLEXITY_MED_MAX=6`, `4→MED`, `7→HIGH` | function undefined |
| T3 | `complexity_band` non-numeric | `complexity_band foo → UNKNOWN` | function undefined |
| T4 | `check_size_thresholds` LOC gate | `check_size_thresholds 800 0 → false`, `801 0 → true` | function undefined |
| T5 | `check_size_thresholds` files gate | `0 8 → false`, `0 9 → true` | function undefined |
| T6 | `check_size_thresholds` config override | `ACORN_LOC_DECOMP_THRESHOLD=100`, `101 0 → true` | function undefined |
| T7 | `enrich_complexity` computes band | feed JSON with dims summing to 13 → output `.complexity.band == "HIGH"`, `.complexity.score == 13`, `.decomposition_required == true` | function undefined |
| T8 | `enrich_complexity` size flag | dims sum 6 (LOW) + `loc_estimate_total=950` → `.size_flag.decomposition_review_required == true`, `.decomposition_required == false` (**proves size gate is independent of band** — Req 3) | function undefined |
| T9 | `enrich_complexity` legacy pass-through | feed legacy 3-key JSON (no `.complexity`) → output byte-identical, no `.complexity` key added | function undefined |
| T10 | `analyze_issue_for_split` extended (mock claude returns dims) | result has `.complexity.band`, AND still `has(should_split,reasoning,sub_issues)` | prompt/enrichment absent → no `.complexity` |
| T11 | `analyze_issue_for_split` backward-compat (mock claude returns legacy 3-key) | result validates 3-key contract, no crash, no `.complexity` | (passes on live base — this is the **positive control** guarding the contract) |
| T12 | `cmd_issue_split` HIGH surfacing | mock `analyze_issue_for_split` to return `band:HIGH`; capture `2>&1`; assert output contains "MUST PROPOSE decomposition" | surfacing code absent |
| T13 | `cmd_issue_split` LOW does NOT surface | mock returns `band:LOW`; assert output does NOT contain "MUST PROPOSE decomposition" | (guards against false-positive; on live base the string is absent for a different reason — see note) |
| T14 | `cmd_issue_split` size-review surfacing | mock returns `size_flag.decomposition_review_required:true`; assert output contains "decomposition review before build" | surfacing code absent |
| T15 | `planning_block_lite/full/quick` contain scoring instruction | each block's output contains "## Complexity Score" and "5-dim" and substituted band cutoffs (e.g. "≤ 7"/"12"), and contains NO literal `__COMPLEXITY_LOW_MAX__` | instruction + placeholders absent |
| T16 | `validate_prompt_md` sentinel extended | render a PROMPT.md via `render_prompt_md` (lite), then `validate_prompt_md` returns 0 and file contains no `__..._THRESHOLD__` tokens | (regression guard) |

**Anti-tautology note (gate-test-drives-real-code):** T7/T8 feed *only* raw dims + totals and assert the band/flag our code *computes* — the expected band is never present in the input, so the test cannot pass by echoing its fixture. T13 is a real negative control paired with T12 (same harness, opposite expectation) to prove the surfacing is band-conditional, not unconditional. This satisfies the PROMPT's "green-by-construction guard is NOT acceptable" constraint.

### 10.2 Prove-it-first procedure (per PROMPT guardrail)

Before writing the fix, run the new test file against the **live-base** `bin/acorn`. Expected: T1–T10, T12, T14, T15, T16 FAIL (undefined functions / missing strings); T11 and T13 pass (contract still holds / string legitimately absent). Record this red baseline in `DONE.md`. Then implement; re-run → all green.

For T13's live-base ambiguity (the "MUST PROPOSE" string is absent on live base for the trivial reason that the whole feature is absent, so it would "pass" vacuously): make T13 meaningful by asserting **both** that a LOW-band mock does NOT emit the string AND that the T12 HIGH-band mock in the *same run* DOES — the pair is only satisfiable by band-conditional code, never by the live base.

### 10.3 Regression suite (must stay green)

Run after implementation:
```bash
bash -n bin/acorn                      # parseable (quality gate, cf. test_rt_gate_removal.sh)
bash test/test_split.sh                # existing split contract + all 9 tests
bash test/test_recon_completeness.sh   # validate_prompt_md / stage manifest
bash test/test_three_artifact.sh       # render_prompt_md three-artifact path
bash test/test_complexity_score.sh     # NEW
```
`test_split.sh` mocks `claude` returning legacy 3-key JSON → exercises the `enrich_complexity` pass-through path → must remain fully green (the real backward-compat proof).

**Out of scope (do not run/modify):** `test_planning_block_clarify.sh`, `test_auto_trigger_clarify_hint.sh` — pre-existing failures from the backed-out clarify feature; PROMPT forbids touching clarify code.

---

## 11. Implementation Order (each step independently verifiable)

1. **Env vars** — add the four `ACORN_COMPLEXITY_*` / `ACORN_*_DECOMP_THRESHOLD` declarations after line 16. Verify: `bash -n bin/acorn`.
2. **Pure helpers** — add `complexity_band`, `check_size_thresholds`, `enrich_complexity` above line 3208 (with in-helper integer-guards for the env thresholds). Verify: T1–T9.
3. **Extend `analyze_issue_for_split`** — prompt block + JSON schema + `enrich_complexity` call before validator. Verify: T10, T11, and `test_split.sh` green.
4. **Display** — extend `format_split_recommendation` (guarded). Verify: manual eyeball + T12/T13 partially.
5. **Surface in `cmd_issue_split`** — HIGH + size warnings after `format_split_recommendation`. Verify: T12, T13, T14.
6. **Planning blocks** — add locals + sed lines + the `## Complexity Score` instruction section in all three `planning_block_*`; renumber Pi Model Recommendation. Verify: T15.
7. **Sentinel** — extend `validate_prompt_md` regex. Verify: T16, `test_recon_completeness.sh` green.
8. **Full regression** — §10.3 suite all green; record red→green baseline in `DONE.md`.

Dependencies: step 2 must precede 3 (enrichment uses helpers); 3 precedes 4/5 (they read enriched JSON); 6 depends on 1 (threshold locals); 7 depends on 6 (new placeholders). Steps 4 and 5 are order-independent of 6/7.

---

## 12. Migration / Rollout

- **No data migration** — no DB, no persisted state; the artifact is the single bash file.
- **No breaking change** — every edit is additive; legacy JSON, legacy tests, and existing PROMPT.md structure are preserved. A downstream caller that ignores `.complexity` sees identical behavior.
- **Deploy is OUT OF SCOPE for this build** (per PROMPT). Build produces branch artifacts + PR-to-fork only. Deploy to `~/acorn/bin` and `~/.foreman/bin` is a separate post-per-merge step with backup (builder-no-pre-gate-live).
- **Rollback** — revert the single commit; because changes are additive and namespaced under `.complexity` / new functions / new env vars, revert is clean with zero residual state.
- **Config rollout** — defaults reproduce the ratified ladder-v4 bands (LOW 5–7 / MED 8–11 / HIGH 12–15) and size gate (800 LOC / 8 files). Operators can retune via env without code change.

---

## 13. Risk Register

| ID | Risk | Sev | Likelihood | Mitigation |
|---|---|---|---|---|
| R1 | Model non-compliance: returns malformed/partial `complexity` block | Med | Med | `enrich_complexity` guard + jq `// 0` coercion → degrades to pass-through or honest-0; never breaks 3-key contract. T9/T11 lock this. |
| R2 | `set -e` trips on a `[ ] &&` boolean assignment in `enrich_complexity` | Med | Low | Use explicit `if…then…fi` form (§5.3 note); `bash -n` + T7/T8 catch regressions. |
| R3 | Unsubstituted `__..._THRESHOLD__` placeholder leaks into PROMPT.md | Med | Low | Add all 4 to `validate_prompt_md` sentinel (§8.3); T16 verifies. |
| R4 | Rubric prose drifts between the 4 copies (split prompt + 3 planning blocks) | Low | Med | Thresholds are single-sourced from env (sed-injected); only static dim-name prose is duplicated. Note in code comment to keep in sync. Acceptable per single-file bash constraint. |
| R5 | Score is advisory only — a HIGH spec can still proceed to build without decomposing | Low | Med | By design: the score *surfaces* the obligation (Req 2 says "MUST PROPOSE", not "MUST block"). Enforcement/gating is a separate future item; noted, not built. |
| R6 | Authoring-time score is model-judgment (not deterministic) unlike the split-path bash math | Low | High | Accepted: SPEC-time score is inherently a judgment from recon/plan; the deterministic core governs the machine-readable split path. Instructions pin the exact cutoffs + format to reduce variance. |
| R7 | Existing `test_split.sh` breaks due to enrichment | High | Low | Enrichment is a strict no-op when `.complexity.dims` absent (every legacy mock). Run `test_split.sh` in step 3. |
| R8 | `jq --argjson` rejects the `true`/`false` strings if a helper accidentally echoes something else | Med | Low | `check_size_thresholds` echoes exactly `true`/`false`; helper unit tests (T4–T6) pin the literal output. |

---

## 14. Pi Model Recommendation (for the downstream implementer)

- **suggested_pi_model: codex** — the spec names exact files, functions, line ranges, and explicit test commands; the work is pattern-following (mirrors existing `analyze_issue_for_split` / `planning_block` / heredoc-sed idioms), touches 2 files, introduces no new interfaces or schemas beyond an additive JSON field, and includes a concrete red→green test procedure. Standing tripwire from PROMPT: any contract-regression or fabricated value → suspend and surface.

---

## 15. Requirements Coverage (self-check)

| Req | Where addressed |
|---|---|
| 1. 5-dim score at spec-authoring time, wired into `issue plan`/create path automatically | §8 (planning-block injection, all 3 modes) + §5/§6 (deterministic core reused on split path) |
| 2. HIGH (≥12) → MUST PROPOSE decomposition unless atomic (record justification) | §8.2 (agent rule) + §7.2 (`cmd_issue_split` HIGH warn) + `atomic_justification` field (§4) |
| 3. Size thresholds (~800 LOC OR >8 files) → decomposition review, independent of band | §5.2 `check_size_thresholds` + §5.3 `size_flag` + §8.2 `size_review` line; T8 proves band-independence |
| 4. Preserve manual path + existing JSON contract (additive) | §4 (additive nesting) + §6.2 (validator untouched) + §9 (degrade-not-break) + T9/T11 + `test_split.sh` regression |
| Guardrail: no `/clarify` touch | §10.3 out-of-scope note; no edits to clarify functions |
| Guardrail: config-over-hardcoding | §3 (4 env vars) + §8.1 (sed-injected cutoffs); no bare magic numbers |
| Guardrail: no-stub / accurate values | §4 provenance + §9 fallbacks; bash owns deterministic math, model estimates from real content |
| Guardrail: prove-it-first tests + non-tautological | §10.2 red baseline + §10.1 anti-tautology note (T7/T8/T12+T13 pair) |
| Guardrail: deploy out of scope | §12 |

