## Work Type
- Bash CLI/runtime behavior change in `bin/acorn`
- Prompt-template hardening for orchestrator stage gates
- Tests + docs updates

## Summary of implementation
- Added configurable retry/failure env vars at top-level:
  - `ACORN_SUBAGENT_RETRY_BUDGET` (default `1`)
  - `ACORN_SUBAGENT_RETRY_BACKOFF_SECONDS` (default `30`)
  - `ACORN_FAILURE_EVENT_PATH` (unset by default)
- Added new stage validation/failure helpers in `bin/acorn`:
  - `stage_manifest`, `stage_name`, `validate_stage_artifacts`
  - `emit_failure_event`, `halt_pipeline_diagnostic`
- Added new internal subcommands:
  - `acorn _internal validate-stage <spec_dir> <mode> <stage>`
  - `acorn _internal halt ...`
  - `acorn _internal emit-failure-event ...`
  - `acorn _internal stage-manifest <mode> <stage>`
- Updated `planning_block_full/lite/quick` to:
  - sanitize retry env vars
  - inject placeholders (`__RETRY_BUDGET__`, `__RETRY_BACKOFF__`, `__EVENT_PATH_DISPLAY__`, `__MODE__`)
  - replace narrative “confirm files exist” with explicit validate/retry/halt stage gates
- Updated `validate_prompt_md` to fail if template placeholders leak into rendered PROMPT.md.
- Updated `status_for_spec` to prefix halted specs with `[HALTED]` on both label and fallback paths.
- Updated `cmd_doctor`:
  - initialize `DOCTOR_FAIL=0`
  - scan all spec dirs for `recon/HALT.md` and `plans/HALT.md` independent of session state
- Updated docs:
  - `README.md` failure handling section
  - `claude/global/CLAUDE.md` failure handling section
- Added test file: `test/test_recon_completeness.sh`.

## RT Review Notes classification and disposition

### MUST-ADDRESS (addressed)
- Stage completion checks were narrative-only → implemented programmatic gate API (`_internal validate-stage`) and prompt gate instructions. (`bin/acorn` planning blocks + helper funcs)
- Per-agent retry budget/backoff placeholders could be stale/invalid → added env sanitization in each planning block function.
- HALT diagnostics/event emission missing → implemented `halt_pipeline_diagnostic` and `emit_failure_event`.
- `DOCTOR_FAIL` uninitialized latent risk → initialized and used in halt scanning flow.
- Halted status not visible in list/status paths consistently → prefixed both `status_for_spec` return paths.
- Recon completeness header requirements (including `## Directory Structure`) → enforced in `stage_manifest` + `validate_stage_artifacts`.
- Full-stage coverage concern (not only stage 0) → added stage-gate instructions across full/lite/quick pipelines.

### ADVISORY (addressed where applicable)
- Path safety for internal halt API → added spec-dir prefix validation in `cmd_internal halt`.
- Placeholder leakage linting → added to `validate_prompt_md`.
- Backward compatibility defaults retained (`retry=1`, events opt-in).
- Event payload structure pinned (`event: subagent.halt`) in JSONL output.

### SPECULATIVE (not required unless concrete)
- Deep semantic quality validation for recon content beyond non-empty+headers (e.g., hallucination detection) not implemented; out-of-scope for current ACs.
- Full subprocess-kill E2E orchestrator simulation remains outside shell-unit scope; covered by helper-level tests and prompt contract.

## Tests run
- `bash -n bin/acorn` → PASS
- `bash test/test_recon_completeness.sh` → PASS (8 passed, 0 failed)
- `bash test/test_path_npm_global.sh` → PASS (6 passed, 0 failed)

## Notes / follow-ups
- Existing `test/test_doctor.sh` has one pre-existing expectation mismatch in this environment (`TD2` expected code differs); not part of this feature’s mandatory verification set used for pass/fail here.
