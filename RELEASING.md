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
4. Build release artifacts with `make package` (unsigned by default).
5. Confirm package content and signature with `./Scripts/verify-package.sh dist/DevStackMenu-*.pkg 0` for unsigned path, or `1` when signing is mandatory.
6. Sanity-check the generated package and confirm it installs with `sudo installer -pkg dist/DevStackMenu-*.pkg -target /`.
7. Sanity-check generated apps in `/Applications` after install.
8. Verify the main app and compose-import helper use distinct bundle identifiers in the built artifacts.
9. Verify single-instance behavior by launching the installed app twice and confirming the second launch exits while the original instance stays alive.
10. If signing credentials are configured, run `workflow_dispatch` on Release Artifacts for signed/notarized output.

## GitHub Release Flow

The repository includes a workflow that builds a `.pkg` artifact and uploads it for tagged releases or manual runs.
Signed/notarized output is optional and driven by workflow secrets.

To enable signing/notarization on `workflow_dispatch`, configure:

- `CODESIGN_INSTALLER_IDENTITY`
- `MACOS_INSTALLER_CERT_P12_BASE64`
- `MACOS_INSTALLER_CERT_PASSWORD`
- `NOTARYTOOL_KEY_ID`
- `NOTARYTOOL_ISSUER_ID`
- `NOTARYTOOL_KEY_P8_BASE64`

Recommended tag format:

```text
v0.1.1
```

## Notes

- Artifacts are unsigned by default.
- `make install-local` is a convenience for maintainers and local users; it is not a substitute for a signed distribution flow.
