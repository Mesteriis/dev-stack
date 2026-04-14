# Title: Target Boundary Deferral

- Status: Accepted
- Date: 2026-04-15
- Supersedes / Superseded by: None

## Context

Pass 2 is scoped to internal refactoring inside the existing `DevStackCore` target.
Profile editor seams were already split to reduce the largest AppKit file pressure.
The remaining request is to avoid introducing new SwiftPM targets before internal service boundaries are stable under normal build/test traffic.

## Decision

Do not introduce additional SwiftPM targets in pass 2.

`DevStackCore` remains a single shipping library with internal folders (`AppActions`, `Menu`, `Runtime`, `Compose`, `Features`, `ProfileEditor`, `Domain`, `Infra`, etc.).

Postpone target extraction to a later pass with explicit validation gates.

## Consequences

- Existing command and install contracts remain unchanged.
- Refactoring stays focused on file-level seams and behavior preservation.
- Future target extraction can be evaluated with clearer call graphs and ownership boundaries.

## Alternatives considered

- Introduce target splits immediately in the same pass.
- Keep all ProfileEditor subflows in one file and defer any splits.

## Migration / Rollback

No migration is required now. If target extraction becomes necessary later, add a new ADR in sequence and update package graph in one bounded migration PR.
