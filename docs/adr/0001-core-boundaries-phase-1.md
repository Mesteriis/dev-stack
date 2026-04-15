# Title: Core Boundaries Phase 1

- Status: Accepted
- Date: 2026-04-14
- Supersedes / Superseded by: None

## Context

`Common.swift`, `RuntimeController.swift`, `ComposeSupport.swift`, and `AppDelegate.swift` accumulated multiple responsibilities and became the main maintenance hotspots in `DevStackCore`.

## Decision

Phase 1 refactoring keeps the existing SwiftPM target graph but introduces internal boundaries:

- `Domain/` for models and validation
- `Infra/` for storage and shell integration
- `Compose/` for compose planning, environment resolution, file generation, and formatting
- `Runtime/` for orchestration services and a thin `RuntimeController` facade
- `Menu/`, `AppActions/`, and coordinators for AppKit menu assembly and app wiring

## Consequences

The first pass reduces file-level coupling without changing install paths, profile formats, or executable names.

## Alternatives considered

- Immediate split into many SwiftPM targets
- Full rewrite of the menu app architecture

## Migration / Rollback

Changes are file-local and reversible. If a boundary proves wrong, move the code back inside `DevStackCore` without changing package products.
