# Changelog

All notable changes to this project will be documented in this file.

The format is inspired by Keep a Changelog, and the project follows a pragmatic release model rather than strict semantic versioning.

## [Unreleased]

## [0.1.3]

### Fixed

- generated compose files now render as YAML instead of JSON, which fixes `docker compose` parse failures on generated profile files
- `dx up` and `dx down` now invoke the real compose runtime actions instead of only toggling profile activation state
- downloaded release package instructions now use a working macOS quarantine-removal command and a robust package selection command
- GitHub Pages deployment is now configured from the repository workflow and no longer depends on manual one-time Pages setup

### Verified

- compose generation was re-checked against `/Users/avm/projects/Work/ecos/state-corp-backend/docker-compose.service.yml`
- regenerated `~/Library/Application Support/DevStackMenu/generated/state-corp-backend/docker-compose.generated.yml` now passes `docker compose -f ... config`

### Added

- Release packaging now ships as `.pkg` (apps + `dx`) and is validated in CI by payload/signature checks.
- Optional macOS installer signing/notarization hooks were added to release workflow for production-like distribution.
- Swift Package Manager repository structure with `Sources/`, `Resources/`, `Scripts/` and maintainer docs
- repository documentation and OSS metadata
- CI workflow for build, test and app bundle smoke build
- smoke-test executable for compose parsing and profile normalization
- architecture, support and release documentation
- dependency update automation and release artifact workflow
- release packaging as a single installer `.pkg` containing menu apps and `dx` CLI
- managed runtime target definitions stored in Application Support
- a runtime setup wizard for local Docker contexts and SSH-backed Docker runtimes
- remote Docker preparation that can verify SSH, create Docker contexts and bootstrap Docker on apt-based hosts
- a single-instance process lock that re-focuses the running menu bar app instead of allowing duplicate launches
- tracked source compose files for imported profiles
- multi-file compose profiles with ordered overlay files
- a global variable manager for shared non-secret env values, including profile assignments and `.env` import
- a Keychain-backed secret manager for compose `${VAR}` references
- compose preview, volume report, metrics report, logs export and remote-file reports opened through the standard macOS viewer
- IDE-aware activation prompts based on open PyCharm and VS Code projects
- AI CLI quota views with progress bars, token highlights and local threshold notifications
- profile deletion with cleanup options for compose volumes and synced data
- file watching for project folders, compose sources and supported IDE state files

### Changed

- app bundle build now writes to `dist/` instead of installing into `~/Applications` by default
- local installation is now handled by `Scripts/install-local.sh`
- `make check` now provides a single local verification entry point
- compose import now supports more real-world port declarations, including host-bound and common long-syntax mappings
- compose planning and runtime generation now use canonical `docker compose config --format json`, with the fallback parser kept only for degraded import scenarios
- the app now manages profile runtime itself instead of delegating orchestration to an external helper CLI
- profile storage moved to the app's own Application Support directory
- profiles now target saved runtime entries instead of duplicating remote Docker connection details inline
- SSH tunnel launch agents now understand managed runtime ports and use stricter non-interactive SSH options
- saved runtimes and raw Docker contexts are now grouped under a single `Runtimes` menu instead of split top-level sections
- remote compose startup now syncs project-relative bind mounts from the project folder and rejects host bind sources outside the project tree
- imported profiles are now automatically removed when their tracked source compose file is deleted
- variable resolution for compose now follows `Variable Manager -> project env files -> Keychain secrets`
- profile activation can keep multiple profiles active across different projects while switching safely within the same project identity
- the app now inspects local CLI/auth logs to show last-known AI tool authorization and quota state where that data is actually available
- the AI CLI menu now renders progress bars, token highlights and local notifications for tracked rate-limit thresholds and projected exhaustion
- the compose-import helper app now uses a distinct bundle identifier from the main menu bar app
