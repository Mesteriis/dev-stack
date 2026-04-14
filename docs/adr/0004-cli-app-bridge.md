# Title: CLI App Bridge

- Status: Accepted
- Date: 2026-04-14
- Supersedes / Superseded by: None

## Context

The `dx` executable is macOS-only and currently bridges into the menu app for focus/open flows, while also driving core runtime workflows.

## Decision

Phase 1 keeps the existing CLI behavior and target layout. The bridge between CLI and AppKit stays narrow and documented instead of being expanded further during this refactor.

## Consequences

Current commands remain intact while future boundary work can isolate the app bridge after core orchestration seams are stable.

## Alternatives considered

- Removing AppKit imports from `dx` in the same pass
- Pulling CLI and app into separate target graphs before internal boundaries settled

## Migration / Rollback

No behavior change is required in pass 1. Later ADRs may replace the bridge with a smaller launcher interface once the core split is stable.
