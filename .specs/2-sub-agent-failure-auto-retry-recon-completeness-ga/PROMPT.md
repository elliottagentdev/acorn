# Feature Spec: Sub-agent failure auto-retry + recon completeness gate before stage advance

## Requirements

## Job Story

When an Acorn sub-agent fails or times out mid-pipeline, I want the pipeline to detect the missing artifact, retry the agent up to N times with backoff, and only advance to the next stage when expected files are present — so I do not get a silently degraded SPEC.md or a crashed downstream stage that requires operator triage.

## Promise

After this ships: Acorn pipelines fail loudly with actionable diagnostics when an agent does not deliver the expected artifact, instead of producing partial spec output that costs an extra RT round and operator time to detect.

## Constraints (upstreamable design)

Per Decision 2 (`elliottagentdev/forge` 2026-05-02): designed for plausible PR-back to upstream `craigmmills/acorn`.

- Retry budget configurable; sane default (1 retry) preserves current behavior for callers that don't override.
- No forge-specific dependencies in the Acorn binary; failure events optionally emit to a configurable target (file path or webhook URL) which forge sets to `~/.foreman/.foreman-events.jsonl` but upstream callers can leave unset.
- Fail-loud philosophy is universally beneficial; not a forge-specific concern.

## Acceptance Criteria

1. **Stage-completion validation**: after each pipeline stage (recon / drafting / validation / synthesis / red-team / final-spec), the orchestrator validates that all expected artifacts exist at the expected paths AND are non-empty. Missing or empty artifact = stage failure.

2. **Per-agent retry**: if a sub-agent fails to produce expected artifact, retry that specific sub-agent once (configurable via `ACORN_SUBAGENT_RETRY_BUDGET`, default 1) with backoff (default 30s). On retry exhaustion, halt the pipeline.

3. **Halt with diagnostics**: on pipeline halt, emit to stderr:
   - Which stage halted
   - Which sub-agent failed
   - Which artifact was expected vs. observed
   - Last 50 lines of the agent's output (if captured)
   - Suggested operator action (manual relaunch / spec dir cleanup / issue review)

4. **Optional event emission**: if `ACORN_FAILURE_EVENT_PATH` env var is set, append a JSONL event to that path with timestamp, slug, stage, agent, artifact, retry_count, halt_reason. Forge consumers point this at `~/.foreman/.foreman-events.jsonl` so Foreman observes acorn failures via the event bus.

5. **Recon completeness gate** (specific case of #1): after Stage 0 in lite/full modes, validate that `recon/architecture.md`, `recon/relevant_code.md`, `recon/conventions.md` ALL exist AND are non-empty AND contain at least the expected section headers (e.g., "## Directory Structure" in architecture.md). Acorn currently has a "Confirm all 3 files exist" instruction in the orchestrator prompt (line 1253) but relies on agent self-verification, which can fail silently.

6. **Test**: induce a Stage 0 sub-agent crash (e.g., kill the Task subprocess); verify pipeline halts with diagnostic; verify SPEC.md not produced (no degraded output); verify event emitted to configured path.

7. **Backwards compatibility**: callers not setting retry env var get current behavior with 1 silent retry (matches Acorn's existing comment at line 1137 "If a sub-agent fails, relaunch it" — formalizes the manual instruction into automation).

## Context

- Surfaced in `elliottagentdev/forge` SDLC review 2026-05-02 (`docs/sdlc-review-2026-05-02.md` §3.2 E-5).
- Wave 1's #125 acorn run hit this: PROMPT.md was stale (round-1 from May 1) and reused without regenerating; took an `acorn clean --force` + restart cycle to fix. With recon completeness validation, the staleness wouldn't have propagated through Stage 0 silently.
- Acorn's current orchestrator prompts include "If a sub-agent fails, relaunch it" (line 1137) and "Confirm all 3 files exist" (line 1253) — these are MANUAL operator instructions that work when the operator is watching, but fail when fire-and-forget execution is desired.

## Suggested wave + labels

Wave 2. Labels: `enhancement`, `bug` (it's both a feature and a defensible bug-class fix).

## Implementation pointers

- Pipeline orchestration is in `/home/agentdev/.local/bin/acorn` (single bash file).
- Stage 0 launches at lines 717-783 (full), 1187-1253 (lite), 1465-1530 (quick).
- Each stage has a "Confirm all N files exist" instruction at the end which is currently human-readable narrative; this issue formalizes it as a programmatic check before stage advance.

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
> to `/home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/images/`. Sub-agents should use the Read tool to examine any images when relevant.

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
- Read the /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/PROMPT.md file that the orchestrator provides in your working directory to understand what feature is being planned.
- Explore the actual codebase using Glob, Grep, and Read tools to understand:
  - Directory layout and project structure
  - Tech stack, frameworks, and languages used
  - Build system and deployment model
  - Key entry points and main modules
  - Database schemas and data layer architecture
  - If /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/images/ exists, use the Read tool to examine any images for visual context (screenshots, mockups, diagrams)
- Write your findings to /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/architecture.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Focus on FACTS about the codebase, not opinions. Reference specific file paths.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/architecture.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**Agent B — Relevant Code:**

```
CRITICAL SUB-AGENT INSTRUCTIONS:
- You are the Relevant Code Reconnaissance agent. You are a SUB-AGENT, not the orchestrator.
- Read the /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/PROMPT.md file that the orchestrator provides in your working directory to understand what feature is being planned.
- Explore the actual codebase using Glob, Grep, and Read tools to identify:
  - Files and modules most likely to be modified for this feature
  - Existing APIs, endpoints, and interfaces relevant to the feature
  - Data models, types, and schemas that would be affected
  - Integration points with external services or systems
  - Related existing functionality that the feature would interact with
- Write your findings to /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/relevant_code.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Include actual code snippets, function signatures, and type definitions. Reference specific file paths and line numbers.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/relevant_code.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**Agent C — Conventions & Constraints:**

```
CRITICAL SUB-AGENT INSTRUCTIONS:
- You are the Conventions Reconnaissance agent. You are a SUB-AGENT, not the orchestrator.
- Read the /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/PROMPT.md file that the orchestrator provides in your working directory to understand what feature is being planned.
- Explore the actual codebase using Glob, Grep, and Read tools to document:
  - Coding style and naming conventions used throughout
  - Error handling patterns (how errors are thrown, caught, reported)
  - Test framework, test file naming, test patterns and helpers
  - CI/CD configuration and quality gates
  - Dependency management approach
  - Existing abstractions and utilities that should be reused
  - Any CLAUDE.md, AGENTS.md, or contributing guidelines
- Write your findings to /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/conventions.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Include concrete examples from the codebase. Reference specific file paths.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/conventions.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**After all 3 complete:** Confirm all 3 files exist (/home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/architecture.md, /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/relevant_code.md, /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/conventions.md), then proceed to Stage 1. Do NOT read the files.

---

### Stage 1: Comprehensive Draft

YOU MUST launch 1 Task tool call. Use model "opus".

**A single drafter balances all four architectural lenses into one comprehensive plan.**

**Prompt:**

```
CRITICAL SUB-AGENT INSTRUCTIONS:
- You are the Plan Drafter. You are a SUB-AGENT, not the orchestrator.
- Read /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/PROMPT.md for full requirements.
- Read /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/architecture.md, /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/relevant_code.md, and /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/conventions.md for codebase context.

Draft a comprehensive implementation plan that balances these four perspectives:
  1. **Minimal Surgery**: Touch the fewest files. Reuse everything that exists. Prefer modifying existing code over creating new files.
  2. **Clean Architecture**: Proper separation of concerns, clear interfaces, extensibility where it matters.
  3. **Robustness**: Error handling, validation, edge cases, rollback and recovery paths.
  4. **Developer Experience**: Simplicity over cleverness. Clear naming. Obvious control flow. Minimal cognitive load.

Cover: architecture, specific file changes with file paths and function signatures, data models, API design, error handling, testing strategy, migration plan, and risks.
Be specific — reference actual file paths, function names, and code patterns from the recon documents.

- Write your plan to /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/plans/draft.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/plans/draft.md"
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
- Read /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/PROMPT.md for the full requirements.
- Read /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/architecture.md, /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/relevant_code.md, and /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/conventions.md for codebase context.
- Read /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/plans/draft.md — this is the plan you must validate.

Perform a combined validation covering four areas:

**1. Requirements Coverage:**
For EACH requirement in /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/PROMPT.md:
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

- Write your validation report to /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/plans/validation.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/plans/validation.md"
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
- Read /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/PROMPT.md for the full requirements.
- Read /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/architecture.md, /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/relevant_code.md, and /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/recon/conventions.md for codebase context.
- Read /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/plans/draft.md (the implementation plan).
- Read /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/plans/validation.md (the validation report).

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

- Write the final spec to /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/plans/SPEC.md
- Write in chunks of ~4000 tokens maximum. Use Write tool first, then Edit tool to append.
- Your final response must be ONLY: "Done. Output: /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/plans/SPEC.md"
- Do NOT return any content, summaries, or explanations. ONLY the done message.
```

**After completion:** Read /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/plans/SPEC.md and present it to the user. This is the ONLY file you read.

---

### Orchestrator Context Management — CRITICAL

**Your context is precious. Sub-agents have their own 200k token contexts. You do NOT.**

- Your ONLY job is to launch Task agents and confirm they completed. That's it.
- You need ~1k tokens per stage. If your context grows beyond ~15k tokens, you broke a rule.
- NEVER read sub-agent output files yourself (the ONLY exception: /home/agentdev/projects/acorn/main/.specs/2-sub-agent-failure-auto-retry-recon-completeness-ga/plans/SPEC.md at the very end)
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
