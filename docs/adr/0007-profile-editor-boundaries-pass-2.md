# Title: Profile Editor Boundaries Pass 2

- Status: Accepted
- Date: 2026-04-14
- Supersedes / Superseded by: None

## Context

`ProfileEditor.swift` remained the largest AppKit surface after phase 1. It mixed window wiring, layout assembly, service editing, compose source/runtime workflows, and compose environment utilities in one file.

The file is still part of one `DevStackCore` target, so the goal is not to introduce new package boundaries. The goal is to create internal seams that let future work touch one workflow without reopening the whole editor.

## Decision

Split the profile editor into focused source files inside `DevStackCore` while keeping one concrete `ProfileEditorWindowController` type:

- keep the window controller shell in `ProfileEditor.swift`
- move layout construction into `ProfileEditor/` support files
- separate runtime and compose-source workflows from compose-environment tooling
- move the service editing dialog into its own file

This is a source-layout refactor only. Stored profile formats, runtime contracts, and editor behavior stay unchanged.

## Consequences

- The main profile editor file becomes smaller and easier to audit
- Environment tooling, runtime selection, and service editing can evolve independently
- AppKit remains in the same target and no protocol layer is introduced just to split the file

## Alternatives considered

- Leaving `ProfileEditor.swift` as the next god file after phase 1
- Replacing the editor with SwiftUI
- Adding separate SwiftPM targets before the editor seams are stable

## Migration / Rollback

This refactor is reversible by collapsing the extension files back into one source file. No data migration or storage rollback is required.
