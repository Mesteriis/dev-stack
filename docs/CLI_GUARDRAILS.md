# CLI Guardrails

The `dx` CLI is a thin surface over DevStackCore.

## Principles

- CLI is NOT a separate product
- CLI does NOT own business logic
- CLI does NOT introduce new storage
- CLI does NOT fork runtime behavior

## Responsibilities

CLI is responsible only for:
- argument parsing
- terminal interaction (wizard / prompts)
- output formatting

All core logic must live in DevStackCore:
- profile management
- compose import and planning
- env validation and generation
- runtime orchestration

## Rule of thumb

If logic exists in CLI but not in DevStackCore — it is a bug.

## Product shape

DevStack = Core + Surfaces

Surfaces:
- AppKit menu bar UI
- dx CLI

Both must use the same core.

## Non-goals

- no full TUI
- no separate CLI-only features
- no duplication of compose/runtime logic
