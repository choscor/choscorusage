# Releasing ChoscorUsage

A release is one Developer ID signed, notarized and stapled DMG attached to a
GitHub Release under an annotated `vX.Y.Z` tag. There is no auto-update channel
(no Sparkle, no appcast): users download the new DMG and replace the app.

Maintainers run the `/release-version` Claude Code skill, which drives the steps
below. `scripts/release/macos.py` never tags or publishes.

## One-time setup

- A **Developer ID Application** certificate and its private key in the login
  Keychain. `security find-identity -v -p codesigning` must list it. With more
  than one, pass `--identity <SHA-1>` or set `CHOSCORUSAGE_SIGNING_IDENTITY`.
- Notary credentials stored in the Keychain, never in the repository:

  ```sh
  xcrun notarytool store-credentials agents-notary --apple-id <id> --team-id <team>
  ```

  Use another profile name with `--notary-profile` or `CHOSCORUSAGE_NOTARY_PROFILE`.
- `gh` authenticated for the `choscor/choscorusage` repository.

## Commands

```sh
python scripts/release/macos.py changes --output build/releases/notes-X.Y.Z/changes.md
python scripts/release/macos.py bump --version X.Y.Z
python scripts/release/macos.py preflight --version X.Y.Z
python scripts/release/macos.py package --version X.Y.Z --output build/releases/X.Y.Z
python scripts/release/macos.py verify --manifest build/releases/X.Y.Z/manifest.json
```

- `changes` writes commits, a file summary and the shipped-code diff since the
  highest `vX.Y.Z` tag (or since the first commit before any release).
- `bump` sets `MARKETING_VERSION` in every configuration and increments
  `CURRENT_PROJECT_VERSION`. The version must increase.
- `preflight` requires a clean checkout, one project version, and a
  `## [X.Y.Z]` section in `CHANGELOG.md`.
- `package` archives the Release configuration with Developer ID and hardened
  runtime, exports it, checks bundle metadata, arm64-only code, the absence of
  `get-task-allow` and of local build paths, notarizes and staples the app,
  builds a signed DMG with an Applications shortcut, notarizes and staples the
  DMG, runs Gatekeeper assessment, and writes `manifest.json` with the source
  commit and DMG SHA-256. The output must be a new directory under `build/`.
  Sanitized tool and notary logs stay in `logs/`.
- `verify` re-hashes the DMG, mounts it read-only, and repeats the signature,
  staple and Gatekeeper checks on the DMG and the app inside it.

## Publishing

Only `ChoscorUsage-X.Y.Z.dmg` is uploaded. The archive, exported app,
notarization zip, manifest and logs stay local in `build/`. Tag the manifest's
`source_commit`, push the tag, then create the release with
`gh release create vX.Y.Z <dmg> --verify-tag`. Never move a pushed tag or
replace a published asset; ship a higher version instead.
