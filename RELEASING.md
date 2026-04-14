# Releasing

## Versioning

The app currently uses a pragmatic release model. Keep these files aligned when cutting a release:

- `Resources/Info.plist`
- `CHANGELOG.md`
- `README.md` if install, menu structure or runtime behavior changed materially

Do not bump `Resources/Info.plist` for ordinary maintenance, documentation sync or unreleased feature commits. Only change the bundle version when you are actually cutting a release.

## Local Release Checklist

1. Run `make check`.
2. Update the unreleased section in `CHANGELOG.md`.
3. If this commit is a real release, bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
4. Build release artifacts with `make app`.
5. Sanity-check the generated apps in `dist/`.
6. Verify the main app and compose-import helper use distinct bundle identifiers in the built artifacts.
7. Verify single-instance behavior by launching the installed app twice and confirming the second launch exits while the original instance stays alive.

## GitHub Release Flow

The repository includes a workflow that can build and upload unsigned app bundles as artifacts for a tagged release or a manual run.

Recommended tag format:

```text
v0.1.0
```

## Notes

- Artifacts are unsigned unless signing is added later.
- `make install-local` is a convenience for maintainers and local users; it is not a substitute for a signed distribution flow.
