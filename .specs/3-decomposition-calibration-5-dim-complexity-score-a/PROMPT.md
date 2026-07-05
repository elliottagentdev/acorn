# Feature Spec: Decomposition-calibration: 5-dim complexity score at spec time plus HIGH-must-propose-decomposition plus LOC-files thresholds

## Requirements

# Acorn decomposition-calibration (Forge substrate, ladder-v4)

**Repo:** elliottagentdev/acorn (OUR fork). **BUILD BASE BRANCH (mandatory):** `forge-acorn-live-base` (commit d83a162 — the byte-exact live-deployed acorn; reconcile-first precondition). Do NOT base on fork/main. **Scope: calibrate decomposition logic only — no unrelated refactors.**

## Problem / grounding (re-grounded on live-base d83a162)
`bin/acorn` `analyze_issue_for_split()` (~line 3208) today is QUALITATIVE + MANUAL: invoked only via `acorn issue split`, using a Claude prompt with generic heuristics (multiple-concerns / independently-shippable / "too large"). There is NO quantitative complexity scoring, NO LOC/files thresholds, and decomposition is NOT surfaced at spec-authoring time. The ladder-v4 baseline doc (model-routing-mapping-v4-ratified-2026-07-05.md, §Decomposition-calibration) requires calibration.

## Requirements (each needs a genuine RED-before-fix shell test / negative control)
1. **5-dim complexity score, emitted at spec-authoring time.** Score every spec on 5 dims, each 1-3: `files_touched`, `LOC_estimate`, `novelty`, `context_depth`, `cross_module_fan_out`. Sum → band: **LOW 5-7 · MED 8-11 · HIGH 12-15**. Record the score + per-dim breakdown in the SPEC header (or spec meta). Wire it into the `acorn issue plan` / spec-authoring path so it is produced automatically, not only on manual `acorn issue split`.
2. **HIGH (≥12) → MUST PROPOSE decomposition.** When a spec scores HIGH, acorn MUST propose decomposition into ≤MED sub-specs, UNLESS it is genuinely atomic (record the atomic-justification when not decomposing). Proposal surfaces at plan time.
3. **Size thresholds → decomposition review.** If the spec estimate exceeds **~800 LOC OR >8 files touched**, flag "decomposition review before build" (independent of the 5-dim band — a belt for large-but-not-HIGH specs).
4. **Preserve the manual path + existing behavior.** `acorn issue split` keeps working; the calibration is ADDITIVE. Do not regress the existing `analyze_issue_for_split` JSON contract (`should_split`/`reasoning`/`sub_issues`); extend it with the score, don't break consumers.

## Guardrails
- **DO NOT touch the pre-Stage-0 /clarify code** (the un-committed backout on the live base). Clarify disposition is a SEPARATE acorn-track item, explicitly out of scope here. Confine changes to decomposition/complexity-scoring code paths.
- Config-over-hardcoding: thresholds (band cutoffs 5-7/8-11/12-15, 800 LOC, 8 files) MUST be overridable via env/config with sensible defaults — no bare magic numbers.
- No-stub / accurate-claims: the scorer must derive from real spec content (recon/plan artifacts), not fabricated values; if a dim can't be estimated, state the fallback honestly.
- Tests: acorn uses shell tests (cf. prior `test(clarify)` shell tests). Add negative-controls that FAIL on the live-base (prove-it-first): a HIGH-scored fixture triggers the decomposition proposal; a LOW/MED fixture does NOT; the 800-LOC / >8-file thresholds fire; the manual `acorn issue split` JSON contract is unchanged. Include a green-by-construction guard (a tautological test that re-asserts its own inputs is NOT acceptable).
- Deploy is OUT OF SCOPE for the build: build produces BRANCH artifacts + PR-to-fork only. Deploy to ~/acorn/bin + ~/.foreman/bin is a SEPARATE post-per-merge step with backup (builder-no-pre-gate-live).

## Complexity (this change, 5-dim): files~2 (bin/acorn + tests) · LOC~2 · novelty~1 · context_depth~2 · fan_out~1 = ~8 → borderline LOW/MED; Strategist ruled LOW lane. Record actual score in SPEC header.
## Dispatch: ladder-v4 LOW → DeepSeek-V4-Pro DeepInfra simple-lane (standing tripwire: any contract-regression/fabrication → suspend to Flash + surface). Record score in SPEC header.

## Discussion / Context

_No discussion comments yet._
---

## PLANNING METHODOLOGY — MANDATORY INSTRUCTIONS (LITE MODE)

> **YOU ARE THE ORCHESTRATOR. YOU MUST FOLLOW THIS METHODOLOGY EXACTLY.**
>
> When the user says "let's draft this" (or any variation like "draft it", "start planning", "go", etc.),
> you MUST execute the 3-stage lite pipeline described below.
>
> **DO NOT write a plan yourself. DO NOT skip stages. DO NOT summarize instead of launching agents.**
>
> If you write ANY plan content yourself instead of delegating to sub-agents via the Task tool,
> you have FAILED. Your ONLY job is to launch Task agents and wait for them to finish.

> **RULES FOR SUB-AGENTS (include these in every sub-agent prompt):**
>
> - Sub-agents write ALL work to files using Write/Edit tools
> - Sub-agents return ONLY: `Done. Output: [filepath]`
> - Sub-agents MUST write in chunks of ~4000 tokens max (Write tool, then Edit to append)
> - Sub-agents must NEVER return content, summaries, or explanations to the orchestrator
> - Violation of these rules will blow up the orchestrator's context window

> **VISUAL ASSETS:** The GitHub issue may include images (screenshots, mockups, diagrams) downloaded
> to `/home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/images/`. Sub-agents should use the Read tool to examine any images when relevant.

---

### Overview

This is the **lite pipeline** — a faster alternative to the full 6-stage pipeline.
It trades multi-draft competition and adversarial red-teaming for speed while keeping
codebase-grounded recon and dedicated validation.

You MUST execute these 4 stages in order. Each stage MUST use the Task tool to launch sub-agents.
You MUST NOT skip any stage. You MUST NOT combine stages. You MUST NOT do the work yourself.

0. **Stage 0**: YOU launch 3 parallel Task agents → each explores the codebase from a different angle
1. **Stage 1**: YOU launch 1 Task agent → drafts a single comprehensive plan balancing all architectural lenses
2. **Stage 2**: YOU launch 1 Task agent → validates the draft against requirements, codebase facts, ambiguities, and edge cases
3. **Stage 3**: YOU launch 1 Task agent → produces final SPEC.md incorporating validation findings

Total: 6 Task agent launches across 4 stages (Stage 0 through Stage 3). No shortcuts.

---

### Stage 0: Codebase Reconnaissance

YOU MUST launch 3 Task tool calls in a SINGLE message (parallel execution). Use model "sonnet".

**Each agent explores the actual codebase to ground all subsequent work in reality.**

**Agent A — Architecture & Structure:**

```
CRITICAL SUB-AGENT INSTRUCTIONS:
- You are the Architecture Reconnaissance agent. You are a SUB-AGENT, not the orchestrator.
- Read the /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/PROMPT.md file that the orchestrator provides in your working directory to understand what feature is being planned.
- Explore the actual codebase using Glob, Grep, and Read tools to understand:
  - Directory layout and project structure
  - Tech stack, frameworks, and languages used
  - Build system and deployment model
  - Key entry points and main modules
  - Database schemas and data layer architecture
  - If /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/images/ exists, use the Read tool to examine any images for visual context (screenshots, mockups, diagrams)
- Write your findings to /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/architecture.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Focus on FACTS about the codebase, not opinions. Reference specific file paths.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/architecture.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**Agent B — Relevant Code:**

```
CRITICAL SUB-AGENT INSTRUCTIONS:
- You are the Relevant Code Reconnaissance agent. You are a SUB-AGENT, not the orchestrator.
- Read the /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/PROMPT.md file that the orchestrator provides in your working directory to understand what feature is being planned.
- Explore the actual codebase using Glob, Grep, and Read tools to identify:
  - Files and modules most likely to be modified for this feature
  - Existing APIs, endpoints, and interfaces relevant to the feature
  - Data models, types, and schemas that would be affected
  - Integration points with external services or systems
  - Related existing functionality that the feature would interact with
- Write your findings to /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/relevant_code.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Include actual code snippets, function signatures, and type definitions. Reference specific file paths and line numbers.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/relevant_code.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**Agent C — Conventions & Constraints:**

```
CRITICAL SUB-AGENT INSTRUCTIONS:
- You are the Conventions Reconnaissance agent. You are a SUB-AGENT, not the orchestrator.
- Read the /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/PROMPT.md file that the orchestrator provides in your working directory to understand what feature is being planned.
- Explore the actual codebase using Glob, Grep, and Read tools to document:
  - Coding style and naming conventions used throughout
  - Error handling patterns (how errors are thrown, caught, reported)
  - Test framework, test file naming, test patterns and helpers
  - CI/CD configuration and quality gates
  - Dependency management approach
  - Existing abstractions and utilities that should be reused
  - Any CLAUDE.md, AGENTS.md, or contributing guidelines
- Write your findings to /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/conventions.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Include concrete examples from the codebase. Reference specific file paths.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/conventions.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**After all 3 complete (Recon Completeness Gate):**
Run stage gate via Bash: `acorn _internal validate-stage "/home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a" lite 0`.
If rc=1, relaunch ONLY failed agent(s), wait `30` seconds between retries, and retry up to `1` times per agent.
On exhaustion, run `acorn _internal halt "/home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a" lite 0 "<agent>" "<artifact>" <halt_reason> "<observed>"` and STOP.
Proceed only if validation exits 0. Do NOT read the files.

---

### Stage 1: Comprehensive Draft

YOU MUST launch 1 Task tool call. Use model "opus".

**A single drafter balances all four architectural lenses into one comprehensive plan.**

**Prompt:**

```
CRITICAL SUB-AGENT INSTRUCTIONS:
- You are the Plan Drafter. You are a SUB-AGENT, not the orchestrator.
- Read /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/PROMPT.md for full requirements.
- Read /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/architecture.md, /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/relevant_code.md, and /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/conventions.md for codebase context.

Draft a comprehensive implementation plan that balances these four perspectives:
  1. **Minimal Surgery**: Touch the fewest files. Reuse everything that exists. Prefer modifying existing code over creating new files.
  2. **Clean Architecture**: Proper separation of concerns, clear interfaces, extensibility where it matters.
  3. **Robustness**: Error handling, validation, edge cases, rollback and recovery paths.
  4. **Developer Experience**: Simplicity over cleverness. Clear naming. Obvious control flow. Minimal cognitive load.

Cover: architecture, specific file changes with file paths and function signatures, data models, API design, error handling, testing strategy, migration plan, and risks.
Be specific — reference actual file paths, function names, and code patterns from the recon documents.

- Write your plan to /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/plans/draft.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/plans/draft.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**After completion (Stage 1 Gate):**
Run stage gate via Bash: `acorn _internal validate-stage "/home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a" lite 1`.
If rc=1, relaunch ONLY failed agent(s), wait `30` seconds between retries, and retry up to `1` times per agent.
On exhaustion, run `acorn _internal halt "/home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a" lite 1 "<agent>" "<artifact>" <halt_reason> "<observed>"` and STOP.
Proceed only if validation exits 0. Do NOT read the file.

---

### Stage 2: Combined Validation

YOU MUST launch 1 Task tool call. Use model "opus".

**A single validator performs requirements coverage, codebase fact-checking, ambiguity audit, and edge case analysis.**

**Prompt:**

```
CRITICAL SUB-AGENT INSTRUCTIONS:
- You are the Plan Validator. You are a SUB-AGENT, not the orchestrator.
- Read /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/PROMPT.md for the full requirements.
- Read /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/architecture.md, /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/relevant_code.md, and /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/conventions.md for codebase context.
- Read /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/plans/draft.md — this is the plan you must validate.

Perform a combined validation covering four areas:

**1. Requirements Coverage:**
For EACH requirement in /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/PROMPT.md:
  - Is it addressed in the plan? WHERE exactly?
  - Is the acceptance criteria testable and specific?
  - What's missing?
Produce a requirements coverage matrix.

**2. Codebase Fact-Check:**
Use Glob, Grep, and Read tools to verify every factual claim in the plan:
  - Do referenced files and directories actually exist?
  - Are function signatures and API contracts correct?
  - Do data models and schemas match what's described?
  - Are there existing utilities the plan reinvents instead of reusing?
Document every factual error: what the plan claims vs what the codebase actually shows.

**3. Ambiguity Audit:**
For each major section:
  - What information is missing that a developer would need?
  - What has multiple valid interpretations?
  - What requires implicit knowledge not stated in the plan?
  - What order-of-operations dependencies are unstated?

**4. Edge Cases & Risks:**
  - Find edge cases NOT handled (empty inputs, concurrent access, partial failures, large data)
  - Find error paths NOT covered (network failures, auth failures, invalid data, timeouts)
  - Find internal contradictions or ordering dependencies that could break
  - Identify security concerns (injection, auth bypass, data exposure)

- Write your validation report to /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/plans/validation.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/plans/validation.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**After completion (Stage 2 Gate):**
Run stage gate via Bash: `acorn _internal validate-stage "/home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a" lite 2`.
If rc=1, relaunch ONLY failed agent(s), wait `30` seconds between retries, and retry up to `1` times per agent.
On exhaustion, run `acorn _internal halt "/home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a" lite 2 "<agent>" "<artifact>" <halt_reason> "<observed>"` and STOP.
Proceed only if validation exits 0. Do NOT read the file.

---

### Stage 3: Final Spec

YOU MUST launch 1 Task tool call. Use model "opus".

**Prompt:**

```
CRITICAL SUB-AGENT INSTRUCTIONS:
- You are the Final Spec agent. You are a SUB-AGENT, not the orchestrator.
- Read /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/PROMPT.md for the full requirements.
- Read /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/architecture.md, /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/relevant_code.md, and /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/recon/conventions.md for codebase context.
- Read /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/plans/draft.md (the implementation plan).
- Read /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/plans/validation.md (the validation report).

Produce the FINAL, COMPLETE implementation specification. It MUST include:

1. **Requirements Traceability Matrix**: For each requirement from the original issue, the exact
   section of this spec that addresses it. Any requirement NOT addressed must be flagged as a gap
   with explicit justification for why it was deferred.

2. **Validation Resolution Log**: For each finding from the validation report, document:
   - The finding (one-line summary)
   - Resolution: how it was fixed in this spec, OR why it was deferred (with justification)
   - Deferred items must include severity and recommended follow-up

3. **Implementation Plan**: Step-by-step instructions with:
   - Specific file paths and function signatures
   - Data models and schema changes
   - Implementation order with dependencies between steps
   - Each step must be independently verifiable

4. **Testing Strategy**: Grounded in the actual test framework and patterns found in recon.
   - Unit tests, integration tests, and edge case tests
   - Specific test file locations and naming conventions
   - Test data and fixture requirements

5. **Risk Register**: Unresolved risks with severity, likelihood, and mitigation strategies.

6. **Pi Model Recommendation**: Based on the full context of this spec, emit a `## Pi Model Recommendation`
   section at the top of SPEC.md (before ## 1. Requirements Traceability Matrix) containing exactly two lines:

   suggested_pi_model: codex
   suggested_pi_model_rationale: <one-line explanation>

   Use value `codex` when: spec names specific files and functions, implementation is pattern-following,
   touches < 8 files, introduces no new interfaces or schemas, includes explicit test commands.
   Use value `opus` when: requirements are vague or exploratory, introduces new architectural patterns,
   crosses subsystem boundaries, adds new interfaces or schemas, touches > 8 files with design judgment required.

The spec must be ready to be handed to a developer or agent for implementation with ZERO questions.

- Write the final spec to /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/plans/SPEC.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/plans/SPEC.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**After completion (Final Stage Gate):**
Run stage gate via Bash: `acorn _internal validate-stage "/home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a" lite 3`.
If rc=1, relaunch ONLY failed agent(s), wait `30` seconds between retries, and retry up to `1` times per agent.
On exhaustion, run `acorn _internal halt "/home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a" lite 3 "<agent>" "<artifact>" <halt_reason> "<observed>"` and STOP.
When validation exits 0, read /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/plans/SPEC.md and present it to the user. This is the ONLY file you read.

---

### Orchestrator Context Management — CRITICAL

**Your context is precious. Sub-agents have their own 200k token contexts. You do NOT.**

- Your ONLY job is to launch Task agents and confirm they completed. That's it.
- You need ~1k tokens per stage. If your context grows beyond ~15k tokens, you broke a rule.
- NEVER read sub-agent output files yourself (the ONLY exception: /home/agentdev/projects/elliottagentdev/acorn/.specs/3-decomposition-calibration-5-dim-complexity-score-a/plans/SPEC.md at the very end)
- NEVER consume sub-agent return messages beyond confirming the word "Done"
- NEVER write plan content yourself — that's what the 6 sub-agents are for
- If validate-stage returns non-zero, relaunch ONLY failed agent(s), wait 30 seconds, and retry up to 1 times per agent. On exhaustion run `acorn _internal halt ...` and STOP. Do NOT do failed work yourself as fallback.


---

## Completion Protocol

When implementation is complete, the implementing agent must:

1. Create or update `DONE.md` in the spec directory (`.specs/<slug>/DONE.md`).
   **IMPORTANT**: Always write to the spec directory, NOT the worktree root.
   For non-repo work (scripts, config, behavioral specs), the spec directory
   is at `<project_root>/<repo>/main/.specs/<slug>/DONE.md`.
2. Include the exact test commands run and their outcomes.
3. For non-repo work, include a `## Work Type` section listing the category
   and primary artifact paths.
4. Summarize file changes and rationale in concise bullet points.
5. List any follow-up risks or deferred work.
