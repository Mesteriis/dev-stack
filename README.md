# DevStackMenu

[![CI](https://github.com/Mesteriis/dev-stack/actions/workflows/ci.yml/badge.svg)](https://github.com/Mesteriis/dev-stack/actions/workflows/ci.yml)
[![Release Artifacts](https://github.com/Mesteriis/dev-stack/actions/workflows/release.yml/badge.svg)](https://github.com/Mesteriis/dev-stack/actions/workflows/release.yml)

<a href="https://www.buymeacoffee.com/mesteriis"><img src="https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=&slug=mesteriis&button_colour=BD5FFF&font_colour=ffffff&font_family=Cookie&outline_colour=000000&coffee_colour=FFDD00" alt="Buy Me a Coffee" /></a>

DevStackMenu is a self-contained macOS menu bar app for managing remote Docker access, compose stacks, shared developer variables and stable developer endpoints from one native AppKit UI.

It provides a native AppKit UI for:

- inspecting status, active profiles, Docker context and compact runtime metrics
- creating managed Docker server entries for local and SSH-backed runtimes
- switching profiles and Docker contexts without relying on an external helper CLI
- starting or stopping tunnel and compose actions
- managing shared env variables and profile-scoped secrets
- importing `docker-compose.yml` files into DevStack profiles

## Status

The project is functional, but still intentionally small and local-first. The repository now follows a conventional OSS layout so it is easier to build, test, review and contribute to.

Repository: [`Mesteriis/dev-stack`](https://github.com/Mesteriis/dev-stack)

## Requirements

- macOS 13 or newer
- Swift 6
- Docker or OrbStack CLI available in `PATH`

## Quick Start

Clone the repository:

```sh
git clone git@github.com:Mesteriis/dev-stack.git
cd dev-stack
```

```sh
make build
make test
make app
make check
```

This produces local app bundles in `dist/`:

- `dist/DevStackMenu.app`
- `dist/Import Compose To DX.app`

To install them into `~/Applications`, run:

```sh
make install-local
```

## What It Does

- shows the current active profile, managed server, tunnel state, Docker context and compact metrics in the macOS menu bar
- stores reusable server definitions in `~/Library/Application Support/DevStackMenu/servers`
- stores imported profile metadata in `~/Library/Application Support/DevStackMenu/profiles`
- stores managed shared env variables in `~/Library/Application Support/DevStackMenu/managed-vars.json`
- uses a runtime lock file at `~/Library/Application Support/DevStackMenu/app.lock` to keep only one app instance alive
- provides a `New Server…` wizard that verifies SSH access, creates the Docker context and can bootstrap Docker on apt-based remote hosts
- switches profiles and Docker contexts without leaving the desktop
- can keep multiple profiles active across different projects while switching safely inside the same project
- prevents duplicate menu bar instances and re-focuses the already running app instead
- opens and edits profile JSON files stored in `~/Library/Application Support/DevStackMenu/profiles`
- plans compose changes through `docker compose config --format json` and falls back to a lightweight parser only for degraded import cases
- syncs project-relative bind mounts to remote servers before `docker compose up` and refuses host paths outside the project tree
- imports compose services into DevStack profiles and opens the result in the profile editor
- supports multi-file compose profiles with a primary file plus additional overlays passed in `docker compose -f ...` order
- includes a global variable manager for non-secret env values, with per-variable profile assignments and `.env` import
- includes a profile-scoped Keychain-backed secret manager for `${VAR}` compose references
- reads IDE state from PyCharm and VS Code on startup and can offer to activate a matching profile automatically
- copies shell exports for the active profile to the clipboard
- shows an `AI CLI Limits` menu for Codex, Sonnet, Qwen and Google with progress bars, token highlights, local authorization and last-known quota status where available
- can raise local notifications when tracked CLI limits cross 25% thresholds or are projected to exhaust before reset
- manages SSH tunnel launch agents itself instead of delegating orchestration to an external helper CLI
- can preview compose changes, open logs, metrics, volume and remote-file reports in the standard macOS viewer
- can delete a profile together with its compose stack, named volumes, project-scoped managed data and synced remote data
- automatically removes imported profiles whose source compose file no longer exists

Typical flow for a remote build host:

1. install the app with `make install-local`
2. open `DevStackMenu`
3. choose `New Server…`
4. enter the SSH host, user and desired Docker context name
5. let the wizard verify or bootstrap Docker and save the server entry
6. create a profile that targets that saved server

## Functional Focus

Current functional priorities:

- making compose import more tolerant of real-world compose files
- keeping the built-in runtime predictable when switching active profiles
- evolving server setup UX around remote Docker preparation and local container modes

Current limitations:

- compose planning/import uses `docker compose config --format json` when Docker is available and falls back to a lightweight parser only as a degraded path
- remote compose sync supports project-relative bind mounts only; absolute host paths outside the project directory are treated as unsupported for remote runs
- managed variables are plain stored config intended for shared dev env values and are applied before project `.env` files; sensitive data should still live in the Keychain-backed secrets flow
- automatic remote Docker bootstrap is currently implemented for apt-based Linux hosts; other distributions still need manual setup
- the `AI CLI Limits` menu is intentionally local-first: Codex gets real last-known rate-limit data from session logs, while other tools may expose only auth state, token usage hints or last quota errors if they do not publish local quota counters
- distribution artifacts are currently unsigned
- UI automation is not in place yet; verification is build + smoke-check oriented

## Menu Model

The current top-level menu is intentionally operational:

- `Status`
- current profile name or `Select Profile`
- `Servers`
- `Variables`
- `AI CLI Limits`
- `Docker Contexts`

Profile-specific actions stay under the current-profile item so switching, runtime control, compose actions, secrets and deletion live in one place.

## Development

Useful commands:

```sh
make build
make test
make app
make check
make clean
```

`make test` runs the repository smoke checks through a small executable target so the project stays verifiable even in command-line macOS environments where the standard test modules are not available.

`make check` runs the full local verification path used in CI: build, smoke checks and app bundle packaging.

Repository layout:

```text
.
├── Sources/
│   ├── DevStackCore/      # AppKit UI + profile/runtime logic
│   └── DevStackMenu/      # executable entry point
├── Sources/DevStackSmokeTests/  # parser and normalization smoke checks
├── Resources/             # Info.plist and AppleScript helper
├── Scripts/               # app bundle build/install scripts
├── docs/                  # architecture and maintainer docs
└── .github/workflows/     # CI
```

## Project Docs

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [RELEASING.md](RELEASING.md)
- [SUPPORT.md](SUPPORT.md)

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). For behavior changes, include a short rationale and keep user-facing workflows in mind; this app is primarily a developer tool, so regressions in profile handling or compose import matter more than cosmetic changes.

If you want to work on functionality first, the most valuable areas are compose import compatibility, profile safety, and clearer feedback around shell-command failures.

## Security

Security reporting instructions are in [SECURITY.md](SECURITY.md).

## License

Released under the MIT License. See [LICENSE](LICENSE).
