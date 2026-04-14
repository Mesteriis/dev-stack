# Contributing

## Workflow

1. Create a focused branch for one change.
2. Run `make check` before opening a PR.
3. If you intentionally skipped one part of `make check`, explain why in the PR.
4. Keep commits small enough to review without reconstructing intent from history.
5. Do not bump `Resources/Info.plist` unless the change is an actual release.

## Change Quality

- Prefer explicit, local changes over broad rewrites.
- Preserve existing behavior unless the PR clearly documents a behavior change.
- Add or update smoke checks for parser, normalization or profile-management logic when practical.
- Treat menu bar UX regressions as real regressions even if the code change is small.
- Keep README and maintainer docs in sync when runtime behavior, menu structure or support expectations change.

## Pull Requests

Each PR should include:

- what problem is being solved
- what behavior changed
- how it was verified
- any follow-up work that remains

## Style

- Follow the repository layout introduced by Swift Package Manager.
- Keep shell scripts POSIX-compatible.
- Avoid adding new dependencies without a clear maintenance reason.
- Update maintainer docs when build, release or support workflow changes.
