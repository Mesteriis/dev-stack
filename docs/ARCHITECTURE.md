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

### `Sources/DevStackCore/AppDelegate.swift`

Owns the status item, menus, refresh loop and user actions.

### `Sources/DevStackCore/Common.swift`

Shared models and helpers:

- profile definitions
- runtime target definitions
- validation and normalization
- CLI path resolution
- shell execution
- profile and runtime-target storage
- compose parsing helpers
- managed variable storage

### `Sources/DevStackCore/ProfileEditor.swift`

The AppKit editor for creating and updating DevStack profiles and services, including runtime-target selection and multi-file compose overlays.

### `Sources/DevStackCore/ServerWizard.swift`

The AppKit setup flow for defining local or SSH-backed runtime targets and preparing their Docker contexts.

### `Sources/DevStackCore/ComposeImport.swift`

The AppKit flow for importing a compose file into a profile editor session.

### `Sources/DevStackCore/VariableManager.swift`

The AppKit manager for non-secret shared env values that can be assigned to one or more profiles and imported from `.env` files.

### `Sources/DevStackCore/SecretManager.swift`

The AppKit manager for profile-scoped Keychain values used to satisfy `${VAR}` compose references.

### `Sources/DevStackCore/SingleInstanceCoordinator.swift`

Owns the process lock used to keep only one menu bar instance alive at a time.

### `Sources/DevStackCore/ProjectContext.swift`

Git and IDE integration used for branch hints, file watching and startup prompts for open projects in PyCharm and VS Code.

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
- the UI is AppKit code-first and not yet separated into smaller presentation components
- smoke checks validate critical logic, but there is no full UI automation
