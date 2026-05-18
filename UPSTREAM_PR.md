# UPSTREAM PR CANDIDATE MEMO

- Topic branch: `forge-262-clarify-stage-integration`
- Source work item: `forge#262` (W4.5-1 `/clarify` pre-Stage-0)
- upstream-pr-candidate: `yes`

## Changes Scope

- `bin/acorn`
  - Adds `stage_manifest()` support for `*:pre0` with clarify artifact header check.
  - Parameterizes clarify artifact filename via `${ACORN_CLARIFICATIONS_FILENAME:-clarifications.md}` in both manifest and pre0 skeleton validation path.
  - Adds `stage_name()` mapping for `pre0` => `pre-stage-0 /clarify`.
  - Routes `halt_pipeline_diagnostic()` `pre*` stages to spec root (`<spec_dir>/HALT.md`).
  - Adds `planning_block_clarify()` using quoted heredoc + sed substitution style (token-safe / no unsubstituted placeholders).
  - Injects clarify pre-stage block into `render_prompt_md()` before planning block when `ACORN_CLARIFY_ENABLED=1`.
  - Extends `write_meta_json()` with stable `clarify_run` boolean derived from env var.
  - Documents clarify env vars in `usage()`.

## Why Upstream-Suitable

- Improves generic Acorn stage pipeline behavior with explicit pre-stage support.
- Avoids hardcoded artifact filename assumptions by honoring env override.
- Preserves existing call signatures and compatibility while adding metadata field safely.
- Uses existing style conventions for heredoc rendering/substitution and gate routing.

## Delineation for Upstream Rebase

- Delineation marker: `forge#262-pre0-clarify-integration`
- Scope is intentionally limited to `bin/acorn` and clarify-stage orchestration/gating behavior.
- No forge-runtime/private repo coupling introduced.

## Test Coverage in Fork

- Fork-side verifier and pytest coverage executed in forge worktree for runtime/acorn stage package.
- Script-level checks validated for `bin/acorn` pre0/clarify anchors and env-parameterized filename behavior.

## Operator Decision

- [ ] Approved to open PR from `elliottagentdev/acorn:forge-262-clarify-stage-integration` to `craigmmills/acorn:main`
- [ ] Hold in fork only (no upstream PR yet)
