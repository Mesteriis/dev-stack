# Title: Runtime Orchestration Services

- Status: Accepted
- Date: 2026-04-14
- Supersedes / Superseded by: None

## Context

`RuntimeController.swift` mixed runtime activation, compose lifecycle, tunnel launchd handling, remote sync, diagnostics, reports, deletion, and remote host preparation.

## Decision

Runtime orchestration is split into focused services:

- `RuntimeStatusService`
- `RuntimeLifecycleService`
- `TunnelService`
- `RemoteSyncService`
- `RuntimeDiagnosticsService`
- `RuntimeDeletionService`
- `RuntimeReportService`

`RuntimeController` remains as a thin compatibility facade that delegates to those services.

## Consequences

Callers keep the same entry points while implementation details gain clearer seams for future extraction and testing.

## Alternatives considered

- Keeping a single static `RuntimeController`
- Introducing protocol-heavy abstractions before the seams were stable

## Migration / Rollback

Facade methods can be repointed back to a single implementation if the split causes regressions. No persistence or CLI contract changes are required.
