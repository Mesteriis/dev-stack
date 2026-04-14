# Title: AI Quota Feature Boundary

- Status: Accepted
- Date: 2026-04-14
- Supersedes / Superseded by: None

## Context

AI CLI quota inspection is useful but orthogonal to Docker/Compose runtime orchestration. Its menu, inspector, and alert logic were spread across generic app files.

## Decision

AI quota logic lives under `Features/AIQuota/` and exposes feature-specific builders/services without expanding into runtime orchestration code.

## Consequences

The feature remains shipped and user-visible, but its code stops distorting core runtime boundaries.

## Alternatives considered

- Removing the feature
- Leaving AI quota menu and alert logic embedded in `AppDelegate`

## Migration / Rollback

The move is internal to `DevStackCore`. Rollback is a file relocation only and does not affect saved data or user workflows.
