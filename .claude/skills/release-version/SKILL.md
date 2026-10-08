---
name: release-version
disable-model-invocation: true
description: Release ChoscorUsage end to end - compare with the latest tag, draft ASD-STE100 release notes with Haiku, bump the version, build, sign, notarize and verify the DMG, then tag and publish a GitHub Release. No auto-update feed.
argument-hint: "[X.Y.Z] [prepare-only]"
---

# Release ChoscorUsage

Work from the repository root. Read [the release guide](../../../docs/RELEASE.md),
[CONTRIBUTING.md](../../../CONTRIBUTING.md) and `CHANGELOG.md` first. Use
`scripts/release/macos.py` for every check, build and verification step; it never
tags or publishes. There is no Sparkle, appcast or other update feed. Do not add one.

## Scope

Arguments: `$ARGUMENTS`. Take the version and scope from them.

- **Full release** (the default, with a version from the arguments or one the user
  confirmed in step 1.4):
  authorizes the release commit, the push of that commit to the default branch,
  the tag push and the GitHub Release. Carry it through without asking again for
  each of those steps.
- **prepare-only**: draft the notes, bump the version, update the changelog and
  run the quality checks. Do not commit, package, tag, push or publish. Packaging
  needs a committed, clean source, so it belongs to a full release.

Use the configured `origin` remote and existing `gh`, Keychain and notary
authentication. Never write a maintainer path, email, Apple ID, team name or
credential into tracked files, notes or commit messages.

## 1. Check the starting state

1. Require a clean working tree on the default branch (`main`). If HEAD is detached
   or on another branch, stop and ask. Do not stash, reset or discard work. The one
   exception: uncommitted changes from a prepare-only run for this same version
   (only the project version and `CHANGELOG.md`). Review them, run steps 1.2 to 1.5,
   then go to section 5. If `build/releases/notes-X.Y.Z/release-notes.md` is
   missing, rebuild it from the existing `## [X.Y.Z]` section of `CHANGELOG.md` in
   the section 4 layout. Do not edit `CHANGELOG.md` again.
2. `git fetch origin --tags` and require `main` to equal or fast-forward
   `origin/main`. A network or authentication failure is an error, not an empty result.
3. Find the previous release: the highest `vX.Y.Z` tag (`macos.py changes` prints
   it as `since`; `null` means this is the first release).
4. Choose the version. Without one in the arguments, propose one from the changes
   (SemVer: breaking change → major, or minor while below 1.0.0; new feature →
   minor; only fixes → patch) and ask the user to confirm. With no previous tag,
   propose the project's current `MARKETING_VERSION` and skip `bump` in section 5.
   Require stable `X.Y.Z`.
5. Require that `vX.Y.Z` exists neither locally, on `origin`
   (`git ls-remote --tags origin vX.Y.Z`), nor as a GitHub Release
   (`gh release view vX.Y.Z`). If any exists, stop and report it. Never move or
   reuse a tag.

## 2. Collect the changes

```sh
python3 scripts/release/macos.py changes --output build/releases/notes-X.Y.Z/changes.md
```

The file holds commit subjects and bodies, a file summary and the shipped-code diff
since the previous tag (or every commit before the first release). Read the file
yourself so you can review the draft against it.

## 3. Draft the notes with Haiku

Call the Agent tool with `model: "haiku"`, `subagent_type: "Explore"` (read-only) and
this prompt, with the placeholders filled in:

```text
You draft user-facing release notes for ChoscorUsage X.Y.Z, a macOS menu bar app that
shows Claude Code and Codex usage limits for several profiles. Read
<absolute path to changes.md> and CHANGELOG.md (the "Unreleased" section) in
<repository root>. Read the whole of both files, not excerpts. Do not edit, create or
run anything else. Reply with Markdown only.

Content rules:
- Describe only effects a user can see or rely on. Leave out tests, CI, refactors,
  tooling, docs-only changes and internal names. Merge related commits into one bullet.
- Every bullet must be supported by the commits or the diff. Do not guess.
- Never include tokens, account IDs, email addresses, local paths or endpoint bodies.
- Group bullets under these headings, in this order, and omit empty ones:
  ## Features (new capabilities), ## Improvements (better existing behavior),
  ## Fixes (corrected wrong behavior), ## Security (user-relevant security fixes),
  ## Upgrade notes (breaking changes, removed or deprecated features, changed
  requirements, migrations, and actions users must take).

Write in ASD-STE100 Simplified Technical English:
- Use only words from the ASD-STE100 dictionary, in their approved meaning and part
  of speech ("show", not "display"; "start", not "launch"; "make sure", not "ensure").
  Technical names and technical verbs are permitted: use product and UI names exactly
  as the app shows them (ChoscorUsage, Claude Code, Codex, Keychain, Settings, Retry).
- One topic per sentence. Maximum 20 words in an instruction, 25 words in a description.
- Use the active voice and the simple present, simple past or simple future tense.
- Write instructions in the imperative ("Open Settings."), one instruction per sentence.
- Do not use "-ing" words except in technical names. Do not use phrasal verbs
  such as "set up" or "find out".
- Keep articles ("the", "a"). Do not make noun clusters of more than three words.
- Do not use contractions, slang, idioms or marketing words ("seamless", "powerful").
- Start each bullet with the subject or the effect, for example:
  "The menu bar shows the highest usage of all visible profiles."
  "ChoscorUsage reads the Codex login from the Keychain when auth.json is absent."
```

Treat the reply as a draft. Check every bullet against `changes.md` and remove or
correct unsupported, internal or private content. Fix any sentence that breaks the
ASD-STE100 rules above (count the words). Do not paste raw commit text.

## 4. Assemble the notes and the changelog

Write `build/releases/notes-X.Y.Z/release-notes.md` (ignored by Git):

```markdown
# X.Y.Z

Released: YYYY-MM-DD

## Features
...reviewed categories, in the order above, without empty headings...

## Downloads and requirements

- Download `ChoscorUsage-X.Y.Z.dmg` below. Open the DMG. Move ChoscorUsage to the
  Applications folder.
- The app does not update automatically. To update, replace the app with the new version.
- The app requires macOS 26 or later on a Mac with Apple silicon.
- SHA-256: `<from manifest.json, added after packaging>`
```

Add `## Known issues` before Downloads only for a verified, current limitation.
Use the intended publication date. In `CHANGELOG.md`, replace the `## Unreleased`
entries with a `## [X.Y.Z] - YYYY-MM-DD` section that holds the same reviewed
category bullets (headings one level down: `### Features`), and keep an empty
`## Unreleased` heading above it. Show the user the notes and continue; apply any
edits they send.

## 5. Bump, check and commit

```sh
python3 scripts/release/macos.py bump --version X.Y.Z   # skip if the project already has X.Y.Z
python3 scripts/ci/quality.py full
```

Fix failures; never weaken a check. Stage only
`ChoscorUsage.xcodeproj/project.pbxproj` and `CHANGELOG.md` by explicit path,
plus any release fix you made. For a full release, commit with:

```text
chore(release): X.Y.Z

Set the app version to X.Y.Z (build N) and record the release notes in
CHANGELOG.md.

Release: vX.Y.Z
```

followed by the repository's commit attribution lines. When `bump` was skipped
(first release), the body says only that the release notes are recorded in
`CHANGELOG.md`.

For prepare-only, leave the changes uncommitted; `preflight` then fails on the
dirty tree, so stop after the quality checks and report.

## 6. Package and verify

```sh
python3 scripts/release/macos.py preflight --version X.Y.Z
python3 scripts/release/macos.py package --version X.Y.Z --output build/releases/X.Y.Z
python3 scripts/release/macos.py verify --manifest build/releases/X.Y.Z/manifest.json
```

`package` takes several minutes because it waits for two notarization submissions;
run it in the background and wait for it. Use a new output directory after an
interrupted run. If it fails, read `build/releases/X.Y.Z/logs/` and fix the cause.
Never bypass signing, notarization or a verification step.

Then install the DMG on this Mac: mount it, copy the app to `/Applications`
(replacing an older copy only after the user agrees), launch it, and confirm that
the menu bar item appears and the menu opens. If you cannot do this check, record it
as pending in the report. Do not claim it passed.

Add the manifest's DMG SHA-256 to the notes.

## 7. Tag and publish (full release only)

Use the manifest's full `source_commit`; it must equal the release commit and HEAD.

```sh
git push origin main
git tag -a vX.Y.Z <source_commit> -m "ChoscorUsage vX.Y.Z"
git push origin refs/tags/vX.Y.Z
gh release create vX.Y.Z build/releases/X.Y.Z/ChoscorUsage-X.Y.Z.dmg --verify-tag \
  --title "ChoscorUsage X.Y.Z" --notes-file build/releases/notes-X.Y.Z/release-notes.md
```

Push `main` only as a fast-forward. Check again that the tag is absent right before
you create it. Upload exactly the one DMG: no wildcards, no other files from
`build/`, no `--clobber`. Then download the public asset to a new directory under
`build/` and compare its SHA-256 with the manifest.

If a step fails after the tag is public, do not delete or move the tag or replace
the asset. Fix forward with a higher version, and tell the user what is public.

## 8. Report

Report the version, build number and source commit; the quality, package and verify
results; the manual install check (passed or pending); the tag push; and the Release
URL with the DMG SHA-256. Separate completed steps from incomplete ones.
