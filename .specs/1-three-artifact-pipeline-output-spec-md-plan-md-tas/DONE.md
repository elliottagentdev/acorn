# DONE — forge#acorn#1

## Summary
Implemented configurable three-artifact output mode in Acorn with backward-compatible default (`single`), prompt augmentation for three-artifact instructions, metadata propagation, and non-fatal approve/spec-complete warnings for missing PLAN.md/TASKS.md.

## Files changed
- `bin/acorn`
  - Added `ACORN_OUTPUT_MODE` defaulting (`line 13`)
  - Added three-artifact prompt block injection in `render_prompt_md` (`1656-1687`)
  - Extended prompt validation for three-artifact mode (`1705-1712`)
  - Extended `write_meta_json` with `output_mode` (`1985-2010`)
  - `cmd_create` reads/validates env mode, threads into render/validate/meta, mismatch warning + mode harmonization, and meta validation (`2303-2391`)
  - `cmd_approve` warnings on missing/empty PLAN.md/TASKS.md in three-artifact mode (`2468-2477`)
  - `cmd_spec_complete` same warning behavior (`2522-2531`)
- `claude/commands/acorn.md`
  - Added PLAN.md/TASKS.md layout docs and Output Modes section.
- `test/test_three_artifact.sh` (new)
  - Added targeted tests for prompt block presence, meta output_mode persistence, and approve warning behavior.

## Tests run
- `bash test/test_three_artifact.sh` ✅
- `bash test/test_labels.sh` ✅
- `bash test/test_auto_trigger.sh` ✅
- `bash test/test_split.sh` ✅
- `bash test/test_dependencies.sh` ✅
- `bash test/test_doctor.sh` ✅
- `bash test/test_idle_detect.sh` ✅
- `bash test/test_images.sh` ✅
- `bash test/test_notify.sh` ✅
- `bash test/test_concurrent_launch.sh` ✅
- `bash test/test_path_npm_global.sh` ✅
- `bash test/test_auth_preflight.sh` ✅

## RT Round-2 classification and disposition

### openai
- **OP-1** → **ADVISORY**. In current code, `dir` is already computed before mismatch check; check runs against existing files and harmonizes output_mode (`bin/acorn:2335-2343`).
- **OP-2** → **MUST-ADDRESS**. Added concrete regression test file for core behavior and documented AC#7 remains manual smoke by nature of LLM pipeline (`test/test_three_artifact.sh`).
- **OP-3** → **MUST-ADDRESS**. Added explicit meta validation after write and warnings when meta read fails (`bin/acorn:2391`, `2472-2473`, `2526-2527`).

### gemini
- **GE-1** → **MUST-ADDRESS**. Prevented prompt/meta desync by forcing `output_mode` back to recorded mode on mismatch when PROMPT.md exists (`bin/acorn:2343`).

### deepseek-v4-pro
- **DE-1** → **SPECULATIVE**. Not applicable to as-built approach because no mktemp-based insertion path is used.
- **DE-2** → **SPECULATIVE**. Not applicable to as-built approach (no sed file-injection pipeline branch requiring pipefail hardening).

### deepseek-v4-flash
- **DE-1** → **SPECULATIVE**. Not applicable (no sed `r`/`d` block implementation shipped).
- **DE-2** → **ADVISORY**. Addressed by explicit "OVERRIDES" wording in appended mode section (`bin/acorn:1663`).
- **DE-3** → **MUST-ADDRESS**. Added concrete runtime test coverage via new test script (prompt + metadata + approve warnings), replacing purely synthetic logic checks.
- **DE-4** → **SPECULATIVE**. Not applicable (no temp-file injection flow).
- **DE-5** → **SPECULATIVE**. Not applicable to as-built templating path.

## Notes
- Backward compatibility preserved: default output mode is `single`.
- No architectural blocker encountered.
