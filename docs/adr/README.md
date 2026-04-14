# ADR Process for DevStackMenu

Use ADRs when a change changes one of these things:

- architectural boundaries (feature, module, or file ownership)
- public/runtime contracts (CLI, storage paths, profile/runtime formats)
- dependency direction or ownership assumptions
- test strategy for important behaviors
- cross-target behavior

No ADR is needed for:

- pure refactors inside an existing boundary
- renames, formatting, or moving code between files without semantic change
- new tests for already-covered behavior

## Naming

- Files use zero-padded 4-digit prefixes: `0000-*.md`.
- `0000-index.md` is required and must be the first numbered file.
- ADR files are append-only with short, stable filenames.

## Status

Use one of:

- `Proposed`
- `Accepted`
- `Superseded`
- `Deprecated`

## ADR format

Each ADR includes:

- Title
- Status
- Date
- Context
- Decision
- Consequences
- Alternatives considered
- Migration / Rollback
- Supersedes / Superseded by

`Date` is `YYYY-MM-DD`.

## Process

- Add a new ADR when scope drift is real and cross-cutting.
- Add it to `0000-index.md` immediately.
- Keep `Scripts/check-adr.sh` passing before merging.
