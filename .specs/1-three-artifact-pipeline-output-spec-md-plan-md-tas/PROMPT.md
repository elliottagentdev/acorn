# Feature Spec: Three-artifact pipeline output (SPEC.md + PLAN.md + TASKS.md) — implements forge#6

## Requirements

## Job Story

When the Acorn pipeline finishes generating a spec, I want the output split into three distinct artifacts — SPEC.md (requirements), PLAN.md (implementation design), TASKS.md (atomic work items with verification commands) — so that Pi sessions and downstream automation can consume the right view for the right purpose without parsing a single mixed-concern document.

## Promise

After this ships: all three Acorn pipeline modes (`quick` / `lite` / `full`) produce three files alongside the existing `plans/SPEC.md`:
- `plans/PLAN.md` — implementation design (architecture, API contracts, data model, alternatives considered)
- `plans/TASKS.md` — structured task list with id, title, size (XS/S/M/L/XL), files affected, verification command, dependencies

## Sub-issue context

This is the implementation half of the operator-facing requirement filed at `elliottagentdev/forge#6` (see that issue for the full Job Story / Promise / operator-side justification).

## Constraints (upstreamable design)

Per Decision 2 (`elliottagentdev/forge` 2026-05-02): changes in this fork should be designed for plausible PR-back to the upstream `craigmmills/acorn`. That means:

- The three-artifact output should be a **configurable behavior** controlled by an Acorn config flag or env var (default-off for backwards-compat; enabled by forge consumers).
- Forge-specific assumptions (e.g., "TASKS.md drives Pi verify-commands extraction") live in Foreman dispatch wrappers, not in the Acorn binary.
- The Acorn binary's pipeline stages emit the three files as siblings in the spec dir; downstream consumers decide what to do with them.
- No coupling to forge-specific paths or conventions inside the binary.

## Acceptance Criteria

1. **Configurable mode**: env var `ACORN_OUTPUT_MODE` (or equivalent CLI flag) with values `single` (current behavior, default for backwards-compat) and `three-artifact`. Forge consumers set `three-artifact`; upstream callers default to `single`.

2. **Stage-level emission** (mode=three-artifact):
   - `quick` mode (Stage 1 / Direct Spec): final agent emits SPEC.md AND a derived PLAN.md AND a derived TASKS.md from the same context.
   - `lite` mode (Stage 3 / Final Spec): same — single agent run produces 3 artifacts.
   - `full` mode (Stage 5 / Final Spec): same — synthesis + RT context informs all three.

3. **PLAN.md schema** (markdown with these sections, in order):
   - Architecture decisions with rationale (1-3 bullet points each; cite alternatives considered)
   - API contracts (inputs / outputs / side effects per touched function or interface)
   - Data model changes (schemas, migrations, atomic-rename patterns)
   - Implementation sequence (phase names + dependencies)
   - Risk register (known unknowns)

4. **TASKS.md schema** (each task as a YAML block):
   ```yaml
   - id: T1
     title: "Add verified_send helper to forged.py"
     size: M  # XS/S/M/L/XL
     files: [runtime/foreman/bin/forged.py]
     verify: "pytest -q runtime/foreman/test/test_forged.py::test_verified_send"
     depends_on: []
   ```
   XL tasks (>8 files OR >3 new interfaces) flagged with `⚠️ XL: requires decomposition` note.

5. **SPEC.md backwards-compat**: in three-artifact mode, SPEC.md trims §3 Implementation Plan and §7 Acceptance Criteria substance (those move to PLAN.md and TASKS.md respectively); SPEC.md remains valid stand-alone (functional requirements, traceability matrix, risk register pointer).

6. **`acorn approve` and `acorn spec-complete`**: warn (not error) if PLAN.md or TASKS.md missing in three-artifact mode. Single-mode unaffected.

7. **Test**: run `acorn create <repo> <issue> --lite` against a representative issue; verify all three files produced; verify SPEC.md still valid stand-alone (legacy consumers can continue to read it).

8. **No new dependencies**: pure prompt and output-parser changes. Bash/jq/awk only.

## Context

- Surfaced in `elliottagentdev/forge` SDLC review 2026-05-02 (`docs/sdlc-review-2026-05-02.md` §3.2 E-13).
- Wave 1 Pi runs hand-extracted verify commands from SPEC.md §7 narrative — adequate for small specs (forge#129) but fragile for larger specs (forge#130 had 7 AC verifier scripts; pulling those out programmatically would have removed manual operator effort).
- Couples to forge NEW-A (Pi context preamble) which extracts verify_commands from TASKS.md when present.
- Couples to forge#83 KM Agent — TASKS.md's structured task IDs become anchors for KM curation ("task T7 was XL and decomposed into T7.a-T7.c during implementation; surface this pattern as a learning").

## Suggested wave + labels

Wave 2 (paired with `elliottagentdev/forge#6`). Labels: `enhancement` (only label that exists in this repo currently).

## Sub-issue link

Implements: `elliottagentdev/forge#6` ("Three-artifact output for Acorn pipeline: SPEC.md + PLAN.md + TASKS.md"). Cross-link both ways.

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
> to `/home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/images/`. Sub-agents should use the Read tool to examine any images when relevant.

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
- Read the /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/PROMPT.md file that the orchestrator provides in your working directory to understand what feature is being planned.
- Explore the actual codebase using Glob, Grep, and Read tools to understand:
  - Directory layout and project structure
  - Tech stack, frameworks, and languages used
  - Build system and deployment model
  - Key entry points and main modules
  - Database schemas and data layer architecture
  - If /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/images/ exists, use the Read tool to examine any images for visual context (screenshots, mockups, diagrams)
- Write your findings to /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/architecture.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Focus on FACTS about the codebase, not opinions. Reference specific file paths.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/architecture.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**Agent B — Relevant Code:**

```
CRITICAL SUB-AGENT INSTRUCTIONS:
- You are the Relevant Code Reconnaissance agent. You are a SUB-AGENT, not the orchestrator.
- Read the /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/PROMPT.md file that the orchestrator provides in your working directory to understand what feature is being planned.
- Explore the actual codebase using Glob, Grep, and Read tools to identify:
  - Files and modules most likely to be modified for this feature
  - Existing APIs, endpoints, and interfaces relevant to the feature
  - Data models, types, and schemas that would be affected
  - Integration points with external services or systems
  - Related existing functionality that the feature would interact with
- Write your findings to /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/relevant_code.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Include actual code snippets, function signatures, and type definitions. Reference specific file paths and line numbers.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/relevant_code.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**Agent C — Conventions & Constraints:**

```
CRITICAL SUB-AGENT INSTRUCTIONS:
- You are the Conventions Reconnaissance agent. You are a SUB-AGENT, not the orchestrator.
- Read the /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/PROMPT.md file that the orchestrator provides in your working directory to understand what feature is being planned.
- Explore the actual codebase using Glob, Grep, and Read tools to document:
  - Coding style and naming conventions used throughout
  - Error handling patterns (how errors are thrown, caught, reported)
  - Test framework, test file naming, test patterns and helpers
  - CI/CD configuration and quality gates
  - Dependency management approach
  - Existing abstractions and utilities that should be reused
  - Any CLAUDE.md, AGENTS.md, or contributing guidelines
- Write your findings to /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/conventions.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Include concrete examples from the codebase. Reference specific file paths.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/conventions.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**After all 3 complete:** Confirm all 3 files exist (/home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/architecture.md, /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/relevant_code.md, /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/conventions.md), then proceed to Stage 1. Do NOT read the files.

---

### Stage 1: Comprehensive Draft

YOU MUST launch 1 Task tool call. Use model "opus".

**A single drafter balances all four architectural lenses into one comprehensive plan.**

**Prompt:**

```
CRITICAL SUB-AGENT INSTRUCTIONS:
- You are the Plan Drafter. You are a SUB-AGENT, not the orchestrator.
- Read /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/PROMPT.md for full requirements.
- Read /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/architecture.md, /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/relevant_code.md, and /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/conventions.md for codebase context.

Draft a comprehensive implementation plan that balances these four perspectives:
  1. **Minimal Surgery**: Touch the fewest files. Reuse everything that exists. Prefer modifying existing code over creating new files.
  2. **Clean Architecture**: Proper separation of concerns, clear interfaces, extensibility where it matters.
  3. **Robustness**: Error handling, validation, edge cases, rollback and recovery paths.
  4. **Developer Experience**: Simplicity over cleverness. Clear naming. Obvious control flow. Minimal cognitive load.

Cover: architecture, specific file changes with file paths and function signatures, data models, API design, error handling, testing strategy, migration plan, and risks.
Be specific — reference actual file paths, function names, and code patterns from the recon documents.

- Write your plan to /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/plans/draft.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/plans/draft.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**After completion:** Confirm the file exists, then proceed to Stage 2. Do NOT read the file.

---

### Stage 2: Combined Validation

YOU MUST launch 1 Task tool call. Use model "opus".

**A single validator performs requirements coverage, codebase fact-checking, ambiguity audit, and edge case analysis.**

**Prompt:**

```
CRITICAL SUB-AGENT INSTRUCTIONS:
- You are the Plan Validator. You are a SUB-AGENT, not the orchestrator.
- Read /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/PROMPT.md for the full requirements.
- Read /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/architecture.md, /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/relevant_code.md, and /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/conventions.md for codebase context.
- Read /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/plans/draft.md — this is the plan you must validate.

Perform a combined validation covering four areas:

**1. Requirements Coverage:**
For EACH requirement in /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/PROMPT.md:
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

- Write your validation report to /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/plans/validation.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/plans/validation.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**After completion:** Confirm the file exists, then proceed to Stage 3. Do NOT read the file.

---

### Stage 3: Final Spec

YOU MUST launch 1 Task tool call. Use model "opus".

**Prompt:**

```
CRITICAL SUB-AGENT INSTRUCTIONS:
- You are the Final Spec agent. You are a SUB-AGENT, not the orchestrator.
- Read /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/PROMPT.md for the full requirements.
- Read /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/architecture.md, /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/relevant_code.md, and /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/recon/conventions.md for codebase context.
- Read /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/plans/draft.md (the implementation plan).
- Read /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/plans/validation.md (the validation report).

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

- Write the final spec to /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/plans/SPEC.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/plans/SPEC.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**After completion:** Read /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/plans/SPEC.md and present it to the user. This is the ONLY file you read.

---

### Orchestrator Context Management — CRITICAL

**Your context is precious. Sub-agents have their own 200k token contexts. You do NOT.**

- Your ONLY job is to launch Task agents and confirm they completed. That's it.
- You need ~1k tokens per stage. If your context grows beyond ~15k tokens, you broke a rule.
- NEVER read sub-agent output files yourself (the ONLY exception: /home/agentdev/projects/acorn/main/.specs/1-three-artifact-pipeline-output-spec-md-plan-md-tas/plans/SPEC.md at the very end)
- NEVER consume sub-agent return messages beyond confirming the word "Done"
- NEVER write plan content yourself — that's what the 6 sub-agents are for
- If a sub-agent fails, relaunch it. Do NOT do its work yourself as a fallback.


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
