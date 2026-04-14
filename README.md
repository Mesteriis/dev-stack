# DevStackMenu

[![CI](https://github.com/Mesteriis/dev-stack/actions/workflows/ci.yml/badge.svg)](https://github.com/Mesteriis/dev-stack/actions/workflows/ci.yml)
[![Release Artifacts](https://github.com/Mesteriis/dev-stack/actions/workflows/release.yml/badge.svg)](https://github.com/Mesteriis/dev-stack/actions/workflows/release.yml)

<a href="https://www.buymeacoffee.com/mesteriis"><img src="https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=&slug=mesteriis&button_colour=BD5FFF&font_colour=ffffff&font_family=Cookie&outline_colour=000000&coffee_colour=FFDD00" alt="Buy Me a Coffee" /></a>

DevStackMenu is a self-contained macOS menu bar app for managing remote Docker access, compose stacks, shared developer variables and stable developer endpoints from one native AppKit UI.

It provides a native AppKit UI for:

- inspecting status, active profiles, Docker context and compact runtime metrics
- creating managed runtime targets for local Docker contexts and SSH-backed remote hosts
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

For a release-style install, build and install the package artifact:

```sh
make package
make install-package
```

For a real root-install smoke-check (installer + pkgutil + post-install checks), run one command:

```sh
./Scripts/release-smoke-install.sh dist/DevStackMenu-*.pkg
```

For signed artifacts:

```sh
./Scripts/release-smoke-install.sh --signed dist/DevStackMenu-*.pkg
```

If you download a release `.pkg` from GitHub instead of building locally, note the current distribution status:

- local `dist/` exists only in your working copy or CI workspace after `make package`
- GitHub Release assets are separate downloaded files and do not appear in your local `dist/`
- unsigned / non-notarized downloaded packages can be blocked by Gatekeeper on macOS

The smoke script verifies:

- package path resolution and signature policy
- required payload entries (`./Applications/DevStackMenu.app`, `./Applications/Import Compose To DX.app`, `./usr/local/bin/dx`)
- package installation through `sudo installer`
- presence of installed artifacts in `/Applications` and `/usr/local/bin`
- CLI entrypoint execution (`dx status`)

The installer places:

- `DevStackMenu.app` and `Import Compose To DX.app` into `/Applications`
- `dx` into `/usr/local/bin`

If an existing DevStack installation is found, the installer will ask whether to remove it before installing:

- `remove` existing files and continue installation
- `keep` keep the current installation unchanged and complete without replacing it
- `abort` install

For non-interactive installs in CI or scripts, set:

```sh
export DEVSTACK_INSTALL_EXISTING_POLICY=remove
```

to replace existing files automatically. Set it to `keep` to preserve the current installation without replacing it.

If installation succeeds, `dx` is available at `/usr/local/bin/dx` and should run immediately in a new shell.
If an existing shell still does not resolve `dx` (rare `zsh` command cache case), reopen the shell or run:

```sh
rehash
```

This `.pkg` is the primary release artifact built by CI.

## Downloaded Release Packages

If macOS blocks an already-downloaded release package with "Apple could not verify it", the package is not notarized yet.

If you trust the release and want to install it manually, remove the quarantine attribute and open it again:

```sh
PKG="$(ls -1t ~/Downloads/DevStackMenu-*.pkg | head -n 1)"
xattr -dr com.apple.quarantine "$PKG"
open "$PKG"
```

Or install directly without Finder:

```sh
PKG="$(ls -1t ~/Downloads/DevStackMenu-*.pkg | head -n 1)"
xattr -dr com.apple.quarantine "$PKG"
sudo installer -pkg "$PKG" -target /
```

If you want Gatekeeper-friendly installs without removing quarantine manually, the release must be signed with Developer ID Installer and notarized. The repository already contains the pipeline hooks for that in `Scripts/sign-notarize-package.sh` and `.github/workflows/release.yml`; it only needs the Apple signing/notarization secrets configured.

## What It Does

- shows the current active profile, managed runtime, tunnel state, Docker context and compact metrics in the macOS menu bar
- stores reusable runtime target definitions in `~/Library/Application Support/DevStackMenu/runtimes`
- stores imported profile metadata in `~/Library/Application Support/DevStackMenu/profiles`
- stores managed shared env variables in `~/Library/Application Support/DevStackMenu/managed-vars.json`
- uses a runtime lock file at `~/Library/Application Support/DevStackMenu/app.lock` to keep only one app instance alive
- provides a `New Runtime…` wizard that verifies SSH access, creates the Docker context and can bootstrap Docker on apt-based remote hosts
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
3. choose `New Runtime…`
4. enter the SSH host, user and desired Docker context name
5. let the wizard verify or bootstrap Docker and save the runtime target
6. create a profile that targets that saved runtime

## Functional Focus

Current functional priorities:

- making compose import more tolerant of real-world compose files
- keeping the built-in runtime predictable when switching active profiles
- evolving runtime setup UX around remote Docker preparation and local container modes

Current limitations:

- compose planning/import uses `docker compose config --format json` when Docker is available and falls back to a lightweight parser only as a degraded path
- remote compose sync supports project-relative bind mounts only; absolute host paths outside the project directory are treated as unsupported for remote runs
- managed variables are plain stored config intended for shared dev env values and are applied before project `.env` files; sensitive data should still live in the Keychain-backed secrets flow
- automatic remote Docker bootstrap is currently implemented for apt-based Linux hosts; other distributions still need manual setup
- the `AI CLI Limits` menu is intentionally local-first: Codex gets real last-known rate-limit data from session logs, while other tools may expose only auth state, token usage hints or last quota errors if they do not publish local quota counters
- distribution artifacts are currently unsigned
- UI automation is not in place yet; verification is build + smoke-check oriented

## Context Utilities

DevStackMenu keeps utilities inside the workflows that already exist instead of adding a separate toolbox.

Current V1 utilities:

- `Compose Environment` inside the profile editor detects `${VAR}` references from the compose config, shows which values are missing, empty, external, managed or already satisfied by Keychain, and lets you fix them in place.
- Missing or empty compose variables can generate values directly from the editor using:
  - secure random strings (`32` or `64`)
  - `UUID v4`
  - `UUID v7`
- While the profile editor is open, DevStack watches the clipboard for Unix timestamps, JSON and base64, then shows a quiet inline preview you can reuse while filling compose env values.

Small examples:

```text
JWT_SECRET is missing
-> Generate…
-> Secure Random (64)
-> Save in Keychain
```

```text
SESSION_ID is missing
-> Generate…
-> UUID v7
-> Save to .env.devstack
```

```text
Copied: 1716000000
-> editor shows Clipboard: Unix timestamp -> 2024-05-18T...
-> Use Result
```

## CLI

DevStackMenu remains the native control plane. The `dx` executable is a thin terminal entrypoint into the same profiles, runtimes, compose parsing and env validation rules that the app already uses.

Build it with the rest of the package:

```sh
swift build
.build/debug/dx status
```

If `dx` is not on your `PATH` yet, you can run the same commands through SwiftPM as `swift run dx <command>`.

Primary V1 flow from a project directory:

```sh
cd /path/to/project
dx add profile -f docker-compose.yml
```

That wizard reuses the app import flow and asks only for:

- profile name
- runtime target
- optional compose overlays
- how to resolve missing `${VAR}` references

Other supported commands:

```sh
dx add server
dx use profile state-corp-backend
dx status
dx env check --profile state-corp-backend
dx up
dx down
```

Small examples:

```text
$ dx status
Profile: state-corp-backend
Runtime: remote-192-168-1-33
Docker context: srv-remote-192-168-1-33
Tunnel: loaded
Compose: state-corp-backend (3 running)
```

```text
$ dx env check --profile state-corp-backend
Profile: state-corp-backend
Working directory: /Users/avm/projects/Work/ecos/state-corp-backend
Compose refs: 8
Unresolved: 1
Environment:
- JWT_SECRET -> Unresolved
- POSTGRES_DB -> .env
- REDIS_URL -> Variable Manager
```

If you run an interactive command in a non-interactive shell, `dx` fails clearly and asks you to rerun it in a TTY.

## Menu Model

The current top-level menu is intentionally operational:

- `Status`
- current profile name or `Select Profile`
- `Runtimes`
- `Variables`
- `AI CLI Limits`

Profile-specific actions stay under the current-profile item so switching, runtime control, compose actions, secrets and deletion live in one place. Raw Docker contexts are now grouped inside `Runtimes`, not split into a separate top-level menu.

## Development

Useful commands:

```sh
make build
make test
make app
make check
make package
make install-package
make clean
```

`make test` runs the repository smoke checks through a small executable target so the project stays verifiable even in command-line macOS environments where the standard test modules are not available.

`make check` runs the full local verification path used in CI: build, smoke checks and app bundle packaging.

Repository layout:

```text
.
├── Sources/
│   ├── DevStackCore/      # AppKit UI + profile/runtime logic
│   ├── dx/                # thin CLI entrypoint
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
- [docs/index.md](docs/index.md) as the documentation hub
- GitHub Docs workflow in [`.github/workflows/docs.yml`](.github/workflows/docs.yml)

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). For behavior changes, include a short rationale and keep user-facing workflows in mind; this app is primarily a developer tool, so regressions in profile handling or compose import matter more than cosmetic changes.

If you want to work on functionality first, the most valuable areas are compose import compatibility, profile safety, and clearer feedback around shell-command failures.

## Security

Security reporting instructions are in [SECURITY.md](SECURITY.md).

## License

Released under the MIT License. See [LICENSE](LICENSE).
