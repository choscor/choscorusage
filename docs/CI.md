# CI and quality gates

`scripts/ci/quality.py` is the single entry point for every check. CI runs only
`quality.py swiftlint-install` and `quality.py full`, so local runs and CI cannot drift.
Every subprocess command is printed before it runs, and any failure exits nonzero.
A missing tool exits with code 2 and prints the command that installs it.

```sh
python scripts/ci/quality.py --help
```

## Stages

| Stage | What it runs |
| --- | --- |
| `swiftlint-install` | Downloads the pinned `portable_swiftlint.zip` into `build/tools/swiftlint/<version>/`, verifies its SHA-256 against `scripts/ci/tools.json`, unpacks the binary, and records the binary's SHA-256. Idempotent: a copy is reused only while the archive still verifies and the binary still matches its recorded hash; lint stages refuse anything else. |
| `format` | `swift format --in-place --recursive` over first-party Swift. Developer convenience; not part of `fast`/`full`. |
| `swift-format` | `swift format lint --strict --recursive` with `.swift-format` (120 columns, 4 spaces), using the swift-format bundled with Xcode. |
| `swiftlint` | Rejects suppressions that are file-wide, cover `all` or several rules, or lack a reason, then runs `swiftlint lint --strict --quiet` (no `--config`, see below) with the pinned binary. |
| `architecture` | `scripts/ci/architecture.py`: the per-layer banned imports and identifiers from `CLAUDE.md`. |
| `file-headers` | `scripts/ci/file_headers.py`: every Swift file opens with a one- or two-line `//` purpose comment that is not just the file name. |
| `secrets-policy` | `scripts/ci/secrets_policy.py`: no `accessToken`, `access_token`, `refreshToken` or `Authorization` inside `print`, `Logger`, `os_log` or `NSLog` calls. |
| `python` | `ruff check`, `ruff format --check`, and `unittest` discovery under `scripts/ci`. |
| `actionlint` | actionlint 1.7.7 over `.github/workflows`. |
| `kit-tests` | `swift test --package-path Packages/ChoscorUsageKit` (Swift 6 mode, `-warnings-as-errors`). |
| `app-build` | `xcodebuild … clean build test CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, logging to `build/xcodebuild.log`. The scheme's test action runs the three package test targets. |
| `swiftlint-analyze` | `swiftlint analyze --strict` with `unused_declaration` and `unused_import` over `build/xcodebuild.log`. |
| **`fast`** | `swift-format`, `swiftlint`, `architecture`, `file-headers`, `secrets-policy`, `python`, `actionlint`, `kit-tests` |
| **`full`** | `fast` plus `app-build` and `swiftlint-analyze` |

## SwiftLint pin

SwiftLint 0.65.1 (latest stable on 2026-10-08). The SHA-256 in `tools.json` was computed
from the downloaded `portable_swiftlint.zip` and matches the asset digest GitHub publishes
for the release (`sha256:c1e429b0…`); the release notes publish checksums only for the
Bazel archive. A Homebrew `swiftlint` on `PATH` is never used. To bump the pin, update
`version`, `url` and `sha256` together and re-run `swiftlint-install`.

## Decisions and deviations recorded during setup

- **`closure_body_length`** has no SwiftUI-builder option in 0.65.1, so the limit is 30
  everywhere and long views are split into subviews; no looser limit was substituted.
- **`todo`** (built in) flags every TODO, including tracked ones, so it is disabled and
  replaced by the `todo_requires_issue` custom rule, which allows `TODO(#12): …`.
- **Suppression reasons** use an ASCII ` - ` separator
  (`// swiftlint:disable:next <rule> - <reason>`). SwiftLint 0.65.1 parses an em dash as
  further rule names and reports them as invalid, so `—` cannot be used.
- **`swiftlint` lints without `--config`.** With `--config`, SwiftLint 0.65.1 ignores nested
  configs, so `Packages/ChoscorUsageKit/Sources/.swiftlint.yml` (which turns on
  `explicit_acl` for package sources) was silently skipped. Without it, SwiftLint finds the
  root `.swiftlint.yml` and merges the nested one. Do not add `--config` back;
  `test_package_sources_require_explicit_access_control` fails if the rule stops applying.
  `swiftlint-analyze` still passes `--config`, which is fine because `explicit_acl` is a lint
  rule, not an analyzer rule.
- **`unused_import`** allows importing `ChoscorUsageKit` for `ChoscorUsageCore` symbols,
  because Kit re-exports Core and the app may import only Kit.
- **`app-build` adds `clean`** so every file's compiler invocation is in the log;
  `swiftlint analyze` silently skips files missing from an incremental build log.
- **swift-format/SwiftLint overlap:** `opening_brace`, `trailing_comma`,
  `vertical_parameter_alignment`, `statement_position`, `indentation_width`,
  `closure_parameter_position`, `multiline_arguments` and `vertical_whitespace` are
  disabled. Running `format` and then `swiftlint` on the code base produces no findings.
- **Seam names:** the clock and environment protocols are `WallClock` and
  `EnvironmentReading`, because `Clock` would shadow Swift's `Clock` and `Environment`
  collides with SwiftUI's `@Environment` in the app (Kit re-exports Core).

## CI runner

`ci.yml` runs on GitHub's `macos-26` image with Xcode 26.5 selected through
`DEVELOPER_DIR` and `xcode-select` (the same build, 17F42, used locally). actionlint 1.7.7
predates that label, so `.github/actionlint.yaml` declares it. `build/tools` is cached by
the hash of `tools.json`; `swiftlint-install` re-verifies the SHA-256 on every cache hit.

`security.yml` runs dependency review on pull requests. On pushes, the weekly schedule
and manual runs, it downloads the SwiftLint archive without the cache and verifies its
SHA-256, so a changed upstream asset is noticed.

All workflow actions are pinned by full commit SHA with a version comment, use
`permissions: contents: read`, `persist-credentials: false`, a cancel-in-progress
concurrency group and per-job timeouts; `test_quality.py` asserts these properties.
