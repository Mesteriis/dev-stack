# Architecture

## Overview

DevStackMenu is a native macOS menu bar application built with AppKit and packaged with Swift Package Manager.

The repository is intentionally small and split into three main targets:

- `DevStackCore`: application logic, AppKit windows, profile persistence and shell integration
- `DevStackMenu`: executable entry point that boots the menu bar app
- `DevStackSmokeTests`: lightweight verification target for parser and normalization checks

## Runtime Model

The app is self-contained at the orchestration layer:

- it stores profiles in its own Application Support directory
- it stores reusable runtime target definitions in its own Application Support directory
- it stores managed shared env variables in its own Application Support directory
- it keeps managed bind-mount data next to the source compose project under `data/<service>`
- it switches Docker contexts directly through the Docker CLI
- it writes and manages launchd plists for SSH tunnels itself
- it runs `docker compose` directly for local container lifecycle
- it prevents duplicate app launches with a process lock in Application Support
- it keeps a lightweight file-watch loop over profile storage, compose project roots and supported IDE state files
- it can prepare remote Docker hosts by checking SSH access, bootstrapping Docker and creating a managed Docker context
- it plans compose operations through `docker compose config --format json`, with a fallback parser only for degraded import scenarios
- it syncs project-relative bind mounts to remote servers before compose startup and rejects host paths outside the project tree
- it removes imported profiles if their tracked source compose file disappears
- it resolves compose env input from managed variables, project env files and Keychain-backed secrets
- it can prompt for profile activation when PyCharm or VS Code already has a matching project open
- it inspects local AI CLI state for Codex, Sonnet, Qwen and Google and exposes last-known auth/quota information, progress bars, token hints and local alerts in the menu bar
- it writes text reports for compose previews, logs, volumes, metrics and remote file listings, then opens them in the standard macOS viewer

There is no external helper CLI dependency in the runtime path anymore.

## Source Layout

Phase 1 keeps one core target, but the code is now split by responsibility inside `DevStackCore`.

### `Sources/DevStackCore/Domain/`

- `Models/`: profile, runtime, compose, environment, and snapshot model types
- `Validation/`: validation errors and normalization helpers

### `Sources/DevStackCore/Infra/`

- `Shell/`: command execution, tool path resolution, shell result types
- `Storage/`: `ProfileStore` and filesystem path contracts

### `Sources/DevStackCore/Compose/`

- `ComposePlan.swift`: compose planning and environment model types
- `ComposePlanBuilder.swift`: normalized compose planning through `docker compose config --format json`
- `ComposeEnvironmentService.swift`: `.env`, managed variable, and missing-env resolution
- `ComposeFileGenerationService.swift`: generated compose YAML emission
- `ComposePreviewFormatter.swift`: plan/report formatting
- `ComposeSecretSupport.swift`: Keychain-backed secret integration

`Sources/DevStackCore/ComposeSupport.swift` now exists only as a thin facade over those services.

### `Sources/DevStackCore/Runtime/`

- `RuntimeStatusService.swift`: docker context discovery, status snapshots, stale profile cleanup
- `RuntimeLifecycleService.swift`: orchestration facade for profile and compose action flows
- `RuntimeComposeFlowService.swift`: profile compose up/down/restart wiring and context switching
- `RuntimeServerPreparationService.swift`: local/remote server checks, bootstrap and context preparation
- `RuntimeProfileHooksService.swift`: hook execution and shell exports helpers
- `TunnelService.swift`: launchd tunnel setup and teardown
- `RemoteSyncService.swift`: managed bind-mount rewrite and remote project sync
- `RuntimeDiagnosticsService.swift`: compose and remote diagnostics
- `RuntimeDeletionService.swift`: deletion plans and cleanup
- `RuntimeReportService.swift`: logs, volumes, metrics, and remote file reports

`Sources/DevStackCore/RuntimeController.swift` is now a thin compatibility facade.

### `Sources/DevStackCore/Menu/`

- menu assembly is split into status, profile, runtimes, variables, and AI limits builders

### `Sources/DevStackCore/AppActions/`

- runtime, profile, and report-related menu actions are grouped by workflow

### `Sources/DevStackCore/Features/AIQuota/`

- `AIToolQuotaInspector.swift`
- `AIToolQuotaInspectionService.swift`
- `AIToolQuotaDataService.swift`
- `AIToolQuotaModels.swift`
- `AILimitAlertManager.swift`
- `AIMenuBuilder.swift`

This keeps AI quota telemetry isolated from runtime orchestration.

### `Sources/DevStackCore/AppDelegate.swift`

`AppDelegate` is reduced to app lifecycle wiring, status item ownership, menu coordination, and shared UI helpers.

### `Sources/DevStackCore/AppRefreshCoordinator.swift`

Owns snapshot collection, watcher refreshes, and IDE activation prompts.

### `Sources/DevStackCore/WindowCoordinator.swift`

Owns editor/import window coordination and profile persistence callbacks.

### Remaining AppKit Windows

- `ProfileEditor.swift`: profile editor shell and shared window helpers
- `ProfileEditor/`: profile editor layout, runtime/compose source flows, environment tooling, and service dialog
- `ServerWizard.swift`: runtime creation and preparation flow
- `ComposeImport.swift`: compose import flow
- `VariableManager.swift`: shared env variable manager
- `VariableManager/VariableManagerDataService.swift`: import/suggested profile support for variable sync
- `VariableManager/VariableManagerDialogs.swift`: add/edit/import modal dialogs
- `SecretManager.swift`: profile secret manager
- `SecretManager/SecretManagerDataService.swift`: secret overview/load/save/delete service methods
- `SecretManager/SecretManagerDialogs.swift`: secret save value dialog

### CLI And Executables

- `Sources/DevStackCore/DXCLI.swift`: CLI parsing and workflow services
- `Sources/dx/main.swift`: CLI command parsing and orchestration entrypoint
- `Sources/dx/DXWorkflowHandlers.swift`: command handlers and helper flow for `dx`
- `Sources/dx/DXTerminal.swift`: terminal I/O helpers for interactive commands
- `Sources/dx/AppLauncher.swift`: macOS app bridge
- `Sources/DevStackMenu/main.swift`: thin app entry point
- `Sources/DevStackSmokeTests/main.swift`: thin smoke runner
- `Sources/DevStackSmokeTests/SmokeChecks.swift`: smoke verification logic kept out of shipping core

### Compatibility Helpers

- `Sources/DevStackCore/Common.swift`: thin compatibility/helper file with shared parsing helpers
- `Sources/DevStackCore/SingleInstanceCoordinator.swift`: single-instance process lock
- `Sources/DevStackCore/ProjectContext.swift`: Git and IDE state integration
- `Sources/DevStackCore/ProfileImportService.swift`: compose import to draft-profile wiring
- `Sources/DevStackCore/ContextUtilities.swift`: value generators and clipboard parsing helpers

## Persistence

Profiles are stored outside the repository in the user's home directory:

- `~/Library/Application Support/DevStackMenu/profiles/*.json`
- `~/Library/Application Support/DevStackMenu/runtimes/*.json`
- `~/Library/Application Support/DevStackMenu/managed-vars.json`
- `~/Library/Application Support/DevStackMenu/current-profile`
- `~/Library/Application Support/DevStackMenu/active-profiles.json`
- `~/Library/Application Support/DevStackMenu/app.lock`
- `~/Library/Application Support/DevStackMenu/generated/...`
- `<compose-project>/<relative-bind-path>`

The app does not maintain its own database.

Env resolution order for compose runs is:

1. managed variables from the global variable manager
2. project env files such as `.env`, `.env.local`, `.env.devstack`
3. generated Keychain-backed secret env file for still-missing `${VAR}` references

## Packaging

The package build creates the executable. App bundle assembly is handled separately in `Scripts/build-app.sh`, which:

1. builds the `DevStackMenu` binary in release mode
2. copies `Resources/Info.plist`
3. assembles `DevStackMenu.app` in `dist/`
4. compiles the AppleScript helper app used for compose-file opening integration with its own bundle identifier

Release distribution is produced through `Scripts/package-release.sh` and uses an unsigned `.pkg` artifact containing:

1. `DevStackMenu.app` in `/Applications`
2. `Import Compose To DX.app` in `/Applications`
3. `dx` binary in `/usr/local/bin`

## Design Constraints

- macOS-only by design
- minimal external dependencies
- local-first workflows over cloud integration
- developer ergonomics matter more than visual complexity

## Current Limitations

- canonical compose planning depends on `docker compose config`; the fallback parser exists only for degraded import scenarios
- remote host bootstrap is currently optimized for apt-based Linux dev hosts
- the profile editor is split by workflow, but still remains an AppKit-heavy surface without dedicated UI tests
- smoke checks validate critical logic, but there is no full UI automation
