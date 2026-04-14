# Title: Smoke Verification Placement

- Status: Accepted
- Date: 2026-04-14
- Supersedes / Superseded by: None

## Context

Smoke verification currently ships from `DevStackCore`, even though `make test` already runs a dedicated executable target.

## Decision

Keep `DevStackSmokeTests` as the executable runner, but move smoke logic into the smoke target area so the shipping core library does not carry the entire smoke harness.

## Consequences

`make test` stays stable, while production code no longer includes the full smoke verification implementation.

## Alternatives considered

- Leaving smoke code in `DevStackCore`
- Replacing smoke checks with SwiftPM test modules in the same pass

## Migration / Rollback

The runner remains thin and keeps the same entry point. Rollback only requires moving the smoke helper file back into `DevStackCore`.
