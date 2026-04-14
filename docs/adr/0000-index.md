# Title: ADR Index

- Status: Accepted
- Date: 2026-04-14
- Supersedes / Superseded by: None

## Context

DevStackMenu already has a compact codebase, but several architectural decisions were implicit and only visible inside large source files.

## Decision

Architecture decisions are tracked in numbered ADR files under `docs/adr/`.

Current ADRs:

- [0001 Core Boundaries Phase 1](0001-core-boundaries-phase-1.md)
- [0002 Runtime Orchestration Services](0002-runtime-orchestration-services.md)
- [0003 Compose Planning Boundary](0003-compose-planning-boundary.md)
- [0004 CLI App Bridge](0004-cli-app-bridge.md)
- [0005 AI Quota Feature Boundary](0005-ai-quota-feature-boundary.md)
- [0006 Smoke Verification Placement](0006-smoke-verification-placement.md)
- [0007 Profile Editor Boundaries Pass 2](0007-profile-editor-boundaries-pass-2.md)

## Consequences

Boundary changes now have a durable record and a stable place for follow-up ADRs.

## Alternatives considered

- Keeping architecture notes only in `docs/ARCHITECTURE.md`
- Capturing decisions only in pull request descriptions

## Migration / Rollback

New ADRs are append-only. If the process stops being useful, freeze the index and link to the last accepted ADR from the architecture guide.
