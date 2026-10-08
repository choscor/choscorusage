# Repository instructions

ChoscorUsage is a macOS 26+, Apple Silicon, menu bar–only SwiftUI app that shows
Claude Code and Codex usage limits for several profiles. Before finishing any
change, run `python3 scripts/ci/quality.py fast`; run `full` when the app target,
the Xcode project or anything the app imports changed. Fix findings rather than
adding suppressions; see "Exceptions and suppressions" below.

## Layer ownership

The UI is thin and the package owns behavior. All logic beyond presentation lives
in the local package `Packages/ChoscorUsageKit`, split into three library targets
whose dependencies point one way only (Core ← Providers ← Kit), so the compiler
rejects reverse imports. The app target imports only `ChoscorUsageKit`, which
re-exports Core's models.

| Target | Owns | May import | Must not use |
| --- | --- | --- | --- |
| `ChoscorUsageCore` | Models (`Profile`, `UsageWindow`, `UsageSnapshot`, `ProfileState`); pure policy (window labels, `MenuBarSummary`, `NotificationPolicy`, refresh/backoff math, Claude Keychain service naming); the seam protocols (`HTTPTransport`, `KeychainReading`, `FileSystem`, `WallClock`, `EnvironmentReading`, `UsageProviding`) | Foundation value types, CryptoKit | `URLSession`, `Security`, `FileManager`, `ProcessInfo`, `os.Logger`, `SwiftUI`, `AppKit`, `UserNotifications`, `ServiceManagement`, `JSONSerialization`/`JSONDecoder` |
| `ChoscorUsageProviders` | Claude and Codex credential readers, endpoint clients and decoders, Codex session-log parsing, profile discovery, and the real seam implementations (URLSession, Security Keychain, FileManager) | Core, Foundation, Security, `os` | `SwiftUI`, `AppKit`, `UserNotifications`, `ServiceManagement` |
| `ChoscorUsageKit` | App-facing orchestration: the `@Observable` `UsageStore`, `UsageRefresher`, `RefreshScheduler`, profile/snapshot/ledger persistence and preferences | Core, Providers, Foundation, `os`, Observation | `SwiftUI`, `AppKit`, `UserNotifications`, `ServiceManagement`, `Security` |
| `ChoscorUsage/` (app) | SwiftUI views (`MenuBarExtra`, Settings), `UNUserNotificationCenter` delivery, `SMAppService` launch at login, wiring real implementations | Kit, SwiftUI, AppKit, UserNotifications, ServiceManagement, Foundation, `os` | `Security`, `URLSession`, direct `ChoscorUsageCore`/`ChoscorUsageProviders` imports |

`scripts/ci/architecture.py` enforces this table. When a view needs a rule,
add it to Core or Kit and test it there; do not compute policy in a view.

- Every external effect sits behind a Core protocol so it can be faked in tests.
- Keep network, Keychain and file I/O off the main actor. Swift 6 language mode
  with complete strict concurrency is on in every target.
- No third-party dependencies. Adding one needs a stated reason in the PR.

## Separation inside a target

- One primary type per file, named after the type.
- Group files by feature (`Claude/`, `Codex/`, `Discovery/`, `System/`).
- No catch-all files (`Utils.swift`, `Helpers.swift`, `Misc.swift`); give shared
  code a named home.
- SwiftLint enforces, as errors: file 400 physical lines, function body 40, type
  body 250, line 120, cyclomatic complexity 10, nesting 2, parameters 5, closure
  body 30. When code does not fit, split it (for SwiftUI, into small subviews);
  never raise a limit or suppress the rule.

## Credentials and privacy

- Read CLI credentials only. Never call a token-refresh endpoint, and never
  write to the Keychain or to any file under a Claude or Codex config directory.
- Read each Claude Keychain item at most once per refresh cycle. After a denial,
  automatic refreshes skip that profile until the user presses Retry.
- Tokens, account IDs and raw response bodies never reach logs, `UserDefaults`,
  notification text or crash output. Use `os.Logger` with `privacy: .private`
  for profile identifiers. The `secrets-policy` gate checks logging calls.
- Test fixtures are synthetic. Never commit real tokens, responses or paths.

## Comments and documentation

- Comments explain *why*: constraints, protocol quirks and tradeoffs. Do not
  narrate what the code does.
- Every Swift file starts with a one- or two-line `//` comment saying what the
  file owns (`file-headers` gate).
- Every public package declaration gets a `///` comment stating its contract:
  inputs, outputs, errors, and the thread or actor it runs on (`missing_docs`).
- Document each undocumented endpoint, header and Keychain naming rule where it
  is used, with a source link and the date it was verified.
- No commented-out code. A TODO must reference an issue: `TODO(#12): …`.

## Exceptions and suppressions

A suppression names one rule on the next line and gives a reason:
`// swiftlint:disable:next <rule> - <reason>`
(SwiftLint 0.65.1 reads only an ASCII ` - ` as the start of the reason). File-wide disables, `all`, and
unexplained disables fail the `swiftlint` stage. Test retries, timeout-only fixes
and weakened assertions are not accepted.

## Verification checklist

- [ ] `python3 scripts/ci/quality.py swiftlint-install` once per pin change.
- [ ] `python3 scripts/ci/quality.py format` before linting Swift you edited.
- [ ] `python3 scripts/ci/quality.py fast` passes.
- [ ] `python3 scripts/ci/quality.py full` passes for app, project or Kit API
      changes (it adds `xcodebuild build test` and `swiftlint analyze`).
- [ ] Behavior changes come with a test through the public seam that failed
      before the change.
- [ ] UI changes were checked in the running app; CI builds are not visual
      verification. Say which in the PR's Verification section.

## Commit messages

Use Conventional Commits. Include a type, scope, description, body, and footer,
with a blank line between each section:

```
<type>(<scope>): <description>

<body>

<footer>
```
