# ADRs

Architecture Decision Records capture changes that affect boundaries, contracts, or operational behavior.

## When An ADR Is Required

Write an ADR when a change:

- moves responsibility between major files or subsystems
- changes storage contracts, CLI surface, install/runtime paths, or compatibility rules
- adds or removes a dependency between package areas or targets
- changes compose/runtime orchestration behavior in a durable way
- changes smoke/test placement or the verification strategy

## When An ADR Is Not Needed

Do not write an ADR for:

- copy edits, comments, and renames with no boundary change
- UI wording, icon, spacing, or other cosmetic AppKit tweaks
- internal refactors that stay inside an already accepted boundary
- bug fixes that restore intended behavior without changing design

## Naming Convention

- File names use `NNNN-kebab-case.md`
- `0000-index.md` is the ADR index
- Numbers are append-only and must stay contiguous
- One ADR records one decision

## Status Model

- `Proposed`: drafted, not yet adopted
- `Accepted`: current decision for the codebase
- `Superseded`: replaced by a newer ADR
- `Rejected`: considered and explicitly not adopted

## Format

Each ADR should stay short and include:

- `Title`
- `Status`
- `Date`
- `Context`
- `Decision`
- `Consequences`
- `Alternatives considered`
- `Migration / Rollback`
- `Supersedes / Superseded by`

## Workflow

1. Copy `template.md`
2. Pick the next sequential number
3. Update `0000-index.md`
4. Run `Scripts/check-adr.sh`
