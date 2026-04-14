# Title: Compose Planning Boundary

- Status: Accepted
- Date: 2026-04-14
- Supersedes / Superseded by: None

## Context

`ComposeSupport.swift` combined normalized compose planning, environment resolution, Keychain-backed secret handling, YAML generation, preview formatting, and fallback import parsing.

## Decision

Compose logic is separated into dedicated files and services:

- `ComposePlan` model types
- `ComposePlanBuilder`
- `ComposeEnvironmentService`
- `ComposeFileGenerationService`
- `ComposePreviewFormatter`
- `ComposeSecretSupport`

`docker compose config --format json` stays the primary planning path. The fallback parser remains limited to degraded import scenarios.

## Consequences

Compose normalization remains stable, while the boundary between planning, env resolution, and output rendering becomes explicit.

## Alternatives considered

- Replacing compose planning with a custom YAML parser
- Leaving secrets and env logic embedded in the planning file

## Migration / Rollback

The public `ComposeSupport` entry points remain available. Rollback only requires collapsing helper files back into one facade implementation.
