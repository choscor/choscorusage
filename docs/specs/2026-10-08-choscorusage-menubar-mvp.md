# ChoscorUsage project setup and menu bar MVP
- Status: Ready for implementation
- Date: 2026-10-08
- Source: Maintainer request to set up `choscorusage`. It is an MIT-licensed, open-source Swift macOS app under https://github.com/choscor that lives only in the menu bar. It tracks Claude Code and Codex usage limits (5h, 7d and other windows) across N profiles, and the project follows the choscor open-source standard in `~/choscor/opensource/choscordb`. The decisions below were settled one at a time with the maintainer in the brainstorm session. The evidence comes from a review of the choscordb repository, web research on the usage endpoints, and read-only metadata checks on the maintainer's machine.

## Outcome and current state

**Beneficiary:** developers who use one or more Claude Code (Pro/Max) and/or Codex CLI (ChatGPT plan) accounts. They want to see, at a glance, how close each account is to its rate-limit windows and when each window resets.

**Current state:** `~/choscor/opensource/choscorusage` is an empty directory. It is not a git repository, and `github.com/choscor/choscorusage` does not exist yet.

**Desired state after this implementation:**
- A public GitHub repo, `choscor/choscorusage`, under the MIT license. It contains a checked-in Xcode app project and a local Swift package. It follows the choscor repository standard below and has green CI.
- A working menu bar–only app, ChoscorUsage. It auto-discovers Claude and Codex profiles and shows each profile's usage windows in a popover. It also offers threshold notifications, launch at login and a configurable refresh interval.
- The signed, notarized release pipeline and Sparkle updates are **out of scope**. They will be covered by a later spec.

### The choscor open-source standard (observed in choscordb)

Mirror these in choscorusage, adapted from Rust/C++/Qt to Swift:
- **Root files:**
  - `README.md`: what the app is, its downloads status, its development commands and its architecture direction.
  - `CONTRIBUTING.md`: anyone may open issues, but **external pull requests are not accepted** and the maintainer implements changes. It also covers the PR title format (`<type>(<scope>): <imperative summary>`), the pre-submit commands, and the exceptions/suppressions policy (narrow, justified, no blanket disables, no test retries or timeout-only fixes).
  - `CHANGELOG.md`: starts with `## Unreleased`.
  - `LICENSE`: MIT for choscorusage; choscordb itself is GPL.
  - `CLAUDE.md`: repository instructions for agents (ownership rules, the verification checklist, and the Conventional Commits format `<type>(<scope>): <description>` with body and footer).
  - `.gitignore` and `.gitattributes`.
- **`.claude/settings.json`:** the same `attribution` block as choscordb, with commit and PR text "🤖 Generated with Claude Code" plus a `Co-Authored-By` line, and `sessionUrl: false`.
- **`.claude/skills/pr-description/`:** adapt this from choscordb's skill. A `release-new-version` skill is deferred along with the release pipeline.
- **`.github/`:**
  - `pull_request_template.md`: copy it with the same sections (Why, What changed, Verification, Review notes, Related issues).
  - `dependabot.yml`: weekly updates on Monday at Asia/Ho_Chi_Minh times, grouped, limited to 5 open PRs. Cover `github-actions`, plus `pip` for `scripts/ci` if it has requirements, plus `swift` if any package dependencies exist.
  - `workflows/ci.yml` and `workflows/security.yml`: `permissions: contents: read`, a concurrency group with cancel-in-progress, actions pinned **by full commit SHA** with a version comment, `persist-credentials: false`, and timeouts on every job. The security workflow runs dependency review on PRs and on a weekly schedule.
- **`scripts/ci/quality.py`:** the single canonical quality entry point.
  - It has `fast` and `full` stages plus focused sub-stages, and `--help`.
  - It prints every subprocess command it runs and exits nonzero on failure.
  - When a tool is missing, it prints an actionable message that includes the install command.
  - CI calls this script and nothing else, so local runs and CI cannot drift apart.
  - It has Python tests (`scripts/ci/test_*.py`), and `requirements.txt` pins its tools. `ruff` is pinned in choscordb; reuse it here for Python lint and format.
- **`docs/`:** `docs/specs/` (this file), `docs/CI.md` and `docs/BUILD.md`.
- **Identity:** the bundle id is `com.choscor.ChoscorUsage`, and the Application Support directory uses the same name.

## Decisions and requirements

### Settled decisions (ledger)

| ID | Decision | Answer / source |
| --- | --- | --- |
| Q1 | Scope of the first implementation | Scaffold plus a working MVP. Signing, notarization, DMG, Sparkle and GitHub Releases are deferred to a later spec (maintainer). |
| Q2 | Usage data source | Read-only calls to the usage endpoints, using each CLI's existing token. **Never refresh or write tokens.** Codex falls back to its local session logs. A statusline cache and log-only modes were rejected (maintainer). |
| Q3 | Profile model | Profiles are auto-discovered on first launch and can be edited manually in Settings: add, remove, rename, reorder and hide (maintainer). |
| Q4 | Menu bar presentation | An icon plus the "worst %", color-tinted at 80% and 95%. The popover lists every visible profile with all its windows (maintainer; see the mockup below). |
| Q5 | Project structure | A thin, checked-in `.xcodeproj` app target (SwiftUI `MenuBarExtra`, `LSUIElement`) plus a local SwiftPM package, `ChoscorUsageKit`, that holds all logic. XcodeGen and SwiftPM-only setups were rejected (maintainer). |
| Q6 | Platform floor | macOS 26.0 or later, Apple Silicon (arm64) only, matching choscordb (maintainer). |
| Q7 | MVP extras | Launch at login, threshold notifications and a configurable refresh interval. A pace/burn-rate hint was excluded (maintainer). |
| Q8 | Repository bootstrap | Run `git init` on `main`, then `gh repo create choscor/choscorusage --public` and push (maintainer). |
| Q9 | License and contribution policy | MIT (maintainer). Issues only, no external PRs (choscor standard). |
| Q10 | Size and complexity limits | Strict, enforced as errors by SwiftLint: file 400 physical lines, function body 40, type body 250, line 120, cyclomatic complexity 10, nesting 2, parameters 5. SwiftLint defaults and choscordb-like looser limits were rejected (maintainer, 2026-10-08 update). |
| Q11 | How SwiftLint is installed | A pinned official portable binary, downloaded and verified by SHA-256 through `quality.py`. Local runs and CI use the same binary. A SwiftPM plugin and Homebrew were rejected (maintainer). |
| Q12 | Formatter vs linter | swift-format (bundled with Xcode) owns layout and auto-fix. SwiftLint owns lint, limits, documentation and static analysis, with its conflicting style rules disabled. SwiftLint-only was rejected (maintainer). |
| Q13 | Comments and documentation | `missing_docs` is required on public declarations in the package. Every Swift file starts with a one-line purpose comment, enforced by a gate. Comment-quality guidance lives in CLAUDE.md and CONTRIBUTING. Requiring docs on everything, and guidance-only, were both rejected (maintainer). |
| Q14 | Separation enforcement | Layered package targets (Core → Providers → Kit → App) with a compiler-enforced direction, plus a `quality.py architecture` gate that bans specific APIs per layer. Two layers and convention-only were rejected (maintainer). |

### Architecture

- **The local Swift package at `Packages/ChoscorUsageKit`** owns all behavior apart from presentation. It is split into three library targets (Q14). Dependencies point in one direction only, so the compiler rejects reverse imports:

  | Target | Owns | May import | Must not use |
  | --- | --- | --- | --- |
  | `ChoscorUsageCore` | Models (`Profile`, `UsageWindow`, `UsageSnapshot`, profile states); pure policy (window normalization and labels, `MenuBarSummary`, `NotificationPolicy`, refresh/backoff math, Claude keychain-service hashing); and the protocols for the injectable seams (`HTTPTransport`, `KeychainReading`, `FileSystem`, `Clock`, `Environment`) | Foundation (value types only: `Date`, `Duration`, `UUID`, string handling), CryptoKit (SHA-256) | `URLSession`, `Security`, `FileManager`, `ProcessInfo`, `os.Logger`, `SwiftUI`, `AppKit`, `UserNotifications`, `ServiceManagement`, `JSONSerialization`/`JSONDecoder` |
  | `ChoscorUsageProviders` | Claude and Codex credential readers, the usage endpoint clients and decoders, Codex session-log parsing, profile discovery, and the real implementations of the Core protocols (URLSession transport, Security keychain reader, FileManager file system) | Core, Foundation, Security, `os` | `SwiftUI`, `AppKit`, `UserNotifications`, `ServiceManagement` |
  | `ChoscorUsageKit` | App-facing orchestration: the `@Observable` `UsageStore`, `UsageRefresher`, `RefreshScheduler`, profile and snapshot persistence, and the preferences model. This is the only module the app imports. | Core, Providers, Foundation, `os`, Observation | `SwiftUI`, `AppKit`, `UserNotifications`, `ServiceManagement`, `Security` (keychain access goes through Providers) |

  Each target has its own test target (`ChoscorUsageCoreTests`, `ChoscorUsageProvidersTests`, `ChoscorUsageKitTests`). This mirrors choscordb's "UI is thin, the core owns behavior" rule. Write the table and the rule into `CLAUDE.md`.
- **Separation inside a target:** keep one primary type per file, named after the type. Group files in folders by feature (for example `Providers/Claude/`, `Providers/Codex/`, `Providers/Discovery/`). Don't use catch-all files such as `Utils.swift` or `Helpers.swift`; give shared code a named home instead.
- **The app target (`ChoscorUsage/`)** owns presentation and OS integration only:
  - the SwiftUI views (`MenuBarExtra` with `.menuBarExtraStyle(.window)`, plus a Settings window)
  - `UNUserNotificationCenter` delivery
  - `SMAppService.mainApp` for launch at login
  - glue code that injects the real implementations of the Kit protocols
- **Swift 6 language mode with strict concurrency.** Use `@Observable` state and `async/await`, and keep network and file I/O off the main actor.
- **No third-party dependencies in the MVP.** The repo uses only Foundation, Security, SwiftUI, UserNotifications and ServiceManagement. This is an assumption that keeps the supply-chain surface at zero; adding a dependency later needs a stated reason. Development tools such as SwiftLint (a pinned and verified binary), swift-format (bundled with Xcode), ruff and actionlint are not app dependencies and are never linked into the app.
- **Injectable seams:** every external effect in the package sits behind a protocol declared in `ChoscorUsageCore` so it can be tested. These are the HTTP transport, the keychain reader, the file system root (home directory), the clock and the environment. Providers supplies the real implementations, and tests supply fakes.

### Profiles

A profile has these fields:
- a stable UUID
- the provider (`claude` | `codex`)
- the config directory path, stored as an absolute string exactly as the user entered it or as discovery found it
- a display name
- an order index
- a hidden flag
- an optional Claude keychain service override

Persist profiles as JSON in `~/Library/Application Support/com.choscor.ChoscorUsage/profiles.json`. Persist preferences (refresh interval, notification toggles) in `UserDefaults`.

**Discovery** runs on first launch and from a "Rescan" button in Settings. The user confirms candidates before they are added. Discovery finds:
- **Claude:**
  - `~/.claude`, plus every `~/.claude*` directory that contains `.credentials.json`, `settings.json` or `projects/`.
  - The `CLAUDE_CONFIG_DIR` value from the app's own environment, if it is set.
  - Every matching keychain service name (see below), so a profile whose credentials live only in the Keychain is still found.
- **Codex:** `~/.codex`, every `~/.codex*` directory that contains `auth.json`, and `$CODEX_HOME` if it is set.

Discovery never adds a directory twice. Paths are compared after standardization, but the stored string stays unchanged.

**Default display names** are derived from the directory name (for example, `.claude-03` becomes "Claude · 03" and `.claude` becomes "Claude"). The user can rename them.

### Credentials (read-only; never logged)

**Claude:**
- **Choosing the keychain service:**
  - The default directory (`~/.claude` with no `CLAUDE_CONFIG_DIR`) uses the generic password service `Claude Code-credentials`. The account is the macOS username.
  - Any other directory uses `Claude Code-credentials-<first 8 lowercase hex chars of SHA-256(UTF-8, NFC-normalized config-dir string)>`. The string is hashed exactly as given, with no tilde expansion and no trailing-slash normalization.
  - Five of six local profiles matched this rule (verified 2026-10-08). The sixth, `~/.claude-personal`, did not match its absolute-path hash, which is likely because it was set with a different spelling such as a trailing slash.
  - When the computed item is missing, Settings shows the profile as "Keychain item not found". It offers a picker listing the `Claude Code-credentials*` service names, which it enumerates by attributes only. Whatever the user picks is saved as the override.
- **Reading the token:**
  - The item's data is JSON with `claudeAiOauth.{accessToken, refreshToken, expiresAt}`. Use only `accessToken` and `expiresAt`.
  - If there is no keychain item, read `<config-dir>/.credentials.json` with the same shape.
  - If both exist, the Keychain wins.
- **Token problems:**
  - If `expiresAt` is in the past, do not call the API. Mark the profile **stale** with the message "Token expired. Run `claude` in this profile to refresh."
  - The app never calls a refresh-token endpoint and never writes to the Keychain or to any file under a CLI config directory.

**Codex:**
- Read `<config-dir>/auth.json` and use `tokens.access_token` and `tokens.account_id`.
- If `auth_mode` indicates API-key mode, or there are no `tokens`, mark the profile "API key mode – no plan limits". This is not an error.
- Never refresh. If the endpoint returns 401, mark the profile stale with "Run `codex login` in this profile."

**Logging:** tokens, account IDs and raw response bodies must never be written to logs, to `UserDefaults`, to notification text or to crash output. Diagnostics use `os.Logger` with a privacy-redacted category for profile identifiers.

**Keychain prompts:**
- Claude Code recreates its keychain item each time it refreshes its token (about every 8 hours), which resets third-party "Always Allow" grants.
- The app reads each Claude keychain item **at most once per refresh cycle**.
- If the user denies access (or presses Cancel), the profile goes into a `keychainDenied` state and **automatic refreshes stop prompting for it**. The popover row shows "Keychain access needed – Retry", and pressing Retry is the only thing that prompts again.
- This avoids a storm of prompts across N profiles.

### Endpoints (undocumented and private; isolate behind one decoder per provider)

**Claude:**
- **Request:** `GET https://api.anthropic.com/api/oauth/usage` with headers `Authorization: Bearer <accessToken>`, `anthropic-beta: oauth-2025-04-20` and `User-Agent: ChoscorUsage/<version>`.
- **Windows to read:** `five_hour`, `seven_day`, `seven_day_opus` and `seven_day_sonnet`. Each has `utilization` (0–100) and `resets_at` (ISO 8601). Any of them may be `null`, and a null window is omitted.
- **Unknown fields** are ignored. Unknown objects with the same `{utilization, resets_at}` shape at the top level are shown as extra windows labelled with their key.
- **Sources:** CodexBar's `docs/claude.md` (https://github.com/steipete/CodexBar/blob/main/docs/claude.md) and community reports. This is undocumented by Anthropic.

**Codex:**
- **Request:** `GET https://chatgpt.com/backend-api/wham/usage` with headers `Authorization: Bearer <access_token>`, `ChatGPT-Account-Id: <account_id>` and `User-Agent: ChoscorUsage/<version>`. If `<config-dir>/config.toml` sets `chatgpt_base_url`, use that as the base URL; a simple key lookup is enough, so no TOML library is needed.
- **Windows to read:** `rate_limit.primary_window` and `rate_limit.secondary_window`, plus each entry of `additional_rate_limits[]`. Each window has `used_percent`, `limit_window_seconds`, `reset_after_seconds` and `reset_at`.
- **Sources:** CodexBar's `docs/codex.md` (https://github.com/steipete/CodexBar/blob/main/docs/codex.md). This is private and undocumented by OpenAI.

**Codex fallback:**
- When the endpoint fails with a network error, a 5xx, or a response that cannot be decoded, read the newest `token_count` event's `rate_limits` from `<config-dir>/sessions/**/*.jsonl`.
- Each entry is shaped `primary` / `secondary` → `{used_percent, window_minutes, resets_at}`. A window may be `null`.
- Scan the newest files first and stop at the first match. Bound the scan to the newest 20 files.
- Show the result with the label "from local log · <age>".
- The fallback is **not** used for 401 (stale) or API-key mode.

**Window normalization:**
- Both providers map to a single `UsageWindow { id, label, usedPercent (0–100, clamped), resetsAt: Date?, windowLength: Duration? }`.
- Labels come from the window length, never from fixed assumptions:
  - 18000s → "5h"
  - 604800s → "7d"
  - 2592000s → "30d"
  - otherwise a humanized duration
- Claude keys map to "5h", "7d", "7d Opus" and "7d Sonnet".
- Plans differ: one local Codex log showed a 43200-minute primary window and a null secondary. The code must therefore not hardcode 5h/7d for Codex.

**HTTP failures:**

| Response | Profile state |
| --- | --- |
| 401 / 403 | `stale` |
| 429 | `rateLimited`. Keep the last good data, back off exponentially with a maximum of 30 minutes, and don't notify. |
| 5xx or transport error | `error`. Keep the last good data, mark it "last updated <age>", and use the Codex fallback where applicable. |
| Decode failure | `unsupportedResponse` ("Usage format changed – update ChoscorUsage"). Never crash. |

Requests have a 15-second timeout. Profiles refresh concurrently, with at most 4 in flight.

### Refresh

- **Interval:** chosen in Settings from 1, 2, 5 (default) or 10 minutes.
- **Refresh now:** a "Refresh" button in the popover refreshes immediately. It is debounced so it can't run more than once every 10 seconds.
- **Automatic triggers:** a refresh also runs when the popover opens, if the data is older than 60 seconds, and after the Mac wakes from sleep.
- **Last good data:** the most recent successful snapshot for each profile is kept in memory and also persisted to Application Support. This lets the popover show it right after launch, marked with its age.

### Menu bar and popover (Q4)

**Menu bar item:** a template SF Symbol gauge plus the text `NN%`.
- `NN` is the highest `usedPercent` across visible profiles, taken from each profile's **shortest** window that has data. For Claude that is "5h"; for Codex it is the shortest window the server returned.
- The text is tinted orange at 80% or more and red at 95% or more.
- When no visible profile has data, show `—`.
- The accessibility label names the profile that supplied the value, for example "Claude · work 72 percent of 5 hour limit".

**Popover:**
- One section per visible profile, in the user's order. Each section shows:
  - the display name and a provider glyph
  - the last-updated age
  - one row per window: label, progress bar, percentage, and time until reset (`↻ 1h12m`)
  - a non-ok state shown inline with its message and any action (Retry or Open Settings)
- The footer has Refresh, Settings… and Quit.

Reference mockup:

```
Menu bar:  [◔ 72%]
┌──────────────────────────────┐
│ Claude · work        ⟳ 1m ago│
│  5h   ███████░░░ 72%  ↻ 1h12m│
│  7d   ███░░░░░░░ 31%  ↻ 3d4h │
│  Opus █░░░░░░░░░ 9%          │
│ Codex · personal             │
│  5h   ██░░░░░░░░ 18%  ↻ 3h40m│
│  wk   ████░░░░░░ 44%  ↻ 5d   │
│ Claude · alt   ⚠ stale – run │
│                  `claude`    │
├──────────────────────────────┤
│ Refresh   Settings…   Quit   │
└──────────────────────────────┘
```

**Settings window** (opened with `SettingsLink` or by activating the app):
- **Profiles tab:** a list with add (directory picker plus provider), remove, rename, drag to reorder, a hide toggle, Rescan, and the Claude keychain-item picker.
- **General tab:** refresh interval, launch at login, and notification toggles.

The app has no Dock icon and no main window; set `LSUIElement = YES`.

### Notifications

- **Requesting permission:** the app asks for notification permission when the user first enables notifications. Notifications are enabled by default, and the request happens on first launch.
- **Thresholds:** for each profile and window, notify when `usedPercent` first crosses **80%**, and again when it crosses **95%**.
- **Reset:** notify "Window reset" when a window that had reached 80% or more passes its reset time, which is seen as `resetsAt` advancing or the percentage dropping below 80%.
- **Dedupe:** the key is `(profileID, windowID, resetsAt, threshold)`. Dedupe state is persisted so a relaunch doesn't notify again.
- **Toggles:** Settings has one toggle for threshold alerts and one for reset alerts.
- **Suppressed cases:** no notifications for stale, error or fallback-only data that is more than 30 minutes old.
- **Content:** the text holds only the display name, the window label and the percentage.

### Launch at login

A Settings toggle backed by `SMAppService.mainApp.register()` / `unregister()`. It shows the actual status, including "requires approval in System Settings" with a button that opens Login Items.

### Repository layout (target)

```
ChoscorUsage.xcodeproj
ChoscorUsage/                       # app target: SwiftUI views, OS glue, Assets, Info.plist
Packages/ChoscorUsageKit/           # Package.swift
  Sources/ChoscorUsageCore/  Sources/ChoscorUsageProviders/  Sources/ChoscorUsageKit/
  Tests/ChoscorUsageCoreTests/  Tests/ChoscorUsageProvidersTests/ (+ Fixtures/)  Tests/ChoscorUsageKitTests/
scripts/ci/quality.py, tools.json, architecture.py, file_headers.py, secrets_policy.py,
           test_*.py, requirements.txt
.swiftlint.yml  .swift-format
docs/specs/, docs/CI.md, docs/BUILD.md
.github/workflows/ci.yml, security.yml, dependabot.yml, pull_request_template.md
.claude/settings.json, .claude/skills/pr-description/
README.md CONTRIBUTING.md CHANGELOG.md LICENSE CLAUDE.md .gitignore .gitattributes .swift-format
```

- **Deployment target:** macOS 26.0. Build arm64 only (`ARCHS = arm64`).
- **Versioning:** the version lives in the Xcode project as `MARKETING_VERSION = 0.1.0` and `CURRENT_PROJECT_VERSION = 1`. `CHANGELOG.md` gets an `## Unreleased` heading.
- **Signing:** local development uses automatic signing with no team, i.e. "Sign to Run Locally". CI builds with `CODE_SIGNING_ALLOWED=NO`.

### Implementation order

1. **Install SwiftLint first, before any Swift code exists.**
   - Add `scripts/ci/tools.json`. It pins the SwiftLint version, the URL of the official `portable_swiftlint.zip` from https://github.com/realm/SwiftLint/releases, and the archive's SHA-256.
   - Pin the latest stable release on the day you implement this. The maintainer's machine has 0.59.1 from Homebrew, so the pin should be that version or newer.
   - Compute the SHA-256 from the downloaded archive and cross-check it against the release's published checksum if one exists. Do not invent it.
   - Add `quality.py swiftlint-install`. It downloads the archive to `build/tools/swiftlint/<version>/`, verifies the SHA-256, makes the binary executable, and is idempotent: if a verified copy already exists, it does nothing.
   - Every stage that uses SwiftLint calls the cached binary and fails with "run `python scripts/ci/quality.py swiftlint-install`" when it's missing.
   - A Homebrew `swiftlint` on PATH is never used.
2. Add `.swiftlint.yml`, `.swift-format` and the remaining gates below, with Python tests for each script. Then scaffold the targets. This order means every Swift file is linted from its very first commit.
3. Continue with the rest of this spec.

### Quality gates (`scripts/ci/quality.py`)

| Stage | What it runs |
| --- | --- |
| `swiftlint-install` | Downloads and verifies the pinned SwiftLint binary. CI runs this before `fast`/`full`. |
| `format` | `swift format --in-place --recursive` on first-party Swift. Developer convenience only; not part of `fast`/`full`. |
| `swift-format` | `swift format lint --strict --recursive` on first-party Swift, using the swift-format bundled with Xcode, configured by `.swift-format` with line length 120 and 4-space indentation |
| `swiftlint` | `swiftlint lint --strict --quiet` from the repo root, without `--config`, so the package's nested config (`explicit_acl`) merges; see docs/CI.md (warnings fail) |
| `architecture` | `scripts/ci/architecture.py`: enforces the banned-API table above, scanning `import` lines and identifiers in each target's sources and in `ChoscorUsage/` |
| `file-headers` | `scripts/ci/file_headers.py`: every first-party `.swift` file must start with a `//` purpose comment of one or two lines. A bare filename doesn't count. |
| `secrets-policy` | Fails if first-party Swift passes token-bearing identifiers (`accessToken`, `access_token`, `refreshToken`, `Authorization`) into `print`, `Logger`, `os_log` or `NSLog` interpolation |
| `python` | `ruff check`, `ruff format --check`, and the Python tests under `scripts/ci` |
| `actionlint` | Pinned 1.7.7, as in choscordb |
| `kit-tests` | `swift test` in `Packages/ChoscorUsageKit`, with warnings as errors and Swift 6 strict concurrency |
| `app-build` | `xcodebuild -project ChoscorUsage.xcodeproj -scheme ChoscorUsage -destination 'platform=macOS,arch=arm64' build test CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, saving the build log to `build/xcodebuild.log` |
| `swiftlint-analyze` | `swiftlint analyze --strict --compiler-log-path build/xcodebuild.log` with `unused_declaration` and `unused_import`. This is the static dead-code check, the Swift counterpart of choscordb's `source_inventory.py`. |
| **`fast`** | `swift-format`, `swiftlint`, `architecture`, `file-headers`, `secrets-policy`, `python`, `actionlint`, `kit-tests` |
| **`full`** | `fast` plus `app-build` and `swiftlint-analyze` |

**`.swiftlint.yml` (Q10, Q12, Q13)**

- **Included paths:** `ChoscorUsage/`, `Packages/ChoscorUsageKit/Sources/` and `Packages/ChoscorUsageKit/Tests/`. Exclude `build/` and `.build/`.
- **Limits (Q10):** `--strict` turns every warning into an error, so each limit is set as both its warning and its error threshold.

  | Rule | Limit |
  | --- | --- |
  | `file_length` | 400, counting comment lines (`ignore_comment_only_lines: false`) |
  | `function_body_length` | 40 |
  | `type_body_length` | 250 |
  | `line_length` | 120, ignoring URLs and comments that contain only a URL |
  | `cyclomatic_complexity` | 10 (`ignores_case_statements: false`) |
  | `nesting` | type level 2, function level 2 |
  | `function_parameter_count` | 5 |
  | `large_tuple` | 3 |
  | `closure_body_length` | 30, but 60 for SwiftUI `body` builder closures if the rule's options allow it; otherwise split the views |

- **Opt-in lint rules:**
  - `missing_docs`, for public declarations
  - `explicit_acl`, in the package only, using a nested `.swiftlint.yml` under `Packages/ChoscorUsageKit/Sources`
  - `force_unwrapping`, `implicitly_unwrapped_optional`, `fatal_error_message`
  - `todo` (a TODO is allowed only when its text contains `#<issue>`, enforced through a `custom_rules` regex)
  - `discouraged_optional_boolean`, `empty_count`, `first_where`, `contains_over_first_not_nil`, `sorted_first_last`, `redundant_type_annotation`, `unused_parameter`, `yoda_condition`
  - `prefer_self_in_static_references`, `private_swiftui_state`, `accessibility_label_for_image`
- **Custom rules:**
  - `no_print`: bans `print(` outside tests. Use `os.Logger`.
  - `no_commented_out_code`: a regex heuristic for lines like `// let `, `// func `, `// if ` and `// }`.
  - `no_catch_all_files`: flags any file named `Utils`, `Helpers` or `Misc`.
- **Analyzer rules:** `unused_declaration`, `unused_import`.
- **Rules disabled to avoid conflicts with swift-format (Q12):** `opening_brace`, `trailing_comma`, `vertical_parameter_alignment`, `statement_position`, `indentation_width`, `closure_parameter_position`, and any other layout rule that fires on swift-format output. The implementer verifies this by running both tools on the scaffolded code; there should be no tool ping-pong.
- **Suppressions:** this follows the CONTRIBUTING exceptions policy. Use `// swiftlint:disable:next <rule> - <reason>` naming a single rule. No file-wide or `all` disables. The `swiftlint` stage also rejects any `swiftlint:disable` without a ` - ` reason, via a custom rule or a check in `quality.py`. (Corrected during implementation: SwiftLint 0.65.1 parses an em dash `—` as further rule names, so the reason separator is an ASCII ` - `; see `docs/CI.md`.)

**Comment guidance (Q13), written into `CLAUDE.md` and `CONTRIBUTING.md`:**
- Comments explain *why*: constraints, protocol quirks and tradeoffs. Don't narrate *what* the code does.
- Every public declaration in the package gets a `///` doc comment that states its contract: inputs, outputs, errors and the thread or actor it runs on.
- No commented-out code. A TODO must reference an issue (`TODO(#12): …`).
- Every undocumented endpoint, header and Keychain naming rule is documented where it's used, with a source link and the date it was verified (for example the SHA-256 service-name rule and the `anthropic-beta` header).
- Each file's purpose comment says what the file owns, in one or two lines.

**Static checks beyond lint:**
- Swift 6 language mode with complete strict concurrency checking in every target.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` in the app, and `-warnings-as-errors` via `unsafeFlags` in the package. Unsafe flags are only allowed for local packages, which this is.
- `swiftlint analyze` in `full`.

- **Note on `secrets-policy`:** keep the Python check small, and give it a Python unit test that proves it catches a violation.
- **CI (`ci.yml`):** runs on a `macos-26` runner (or the nearest available image with Xcode 26). It selects a pinned Xcode with `xcode-select`, installs `scripts/ci/requirements.txt` and actionlint, runs `python scripts/ci/quality.py swiftlint-install`, and then runs `python scripts/ci/quality.py full`. Cache `build/tools/` keyed on the hash of `tools.json`; the SHA-256 is verified again on every cache hit.

## Acceptance criteria and public test seams

| Criterion | Observable seam |
| --- | --- |
| The repo follows the choscor standard: MIT `LICENSE`, README, CONTRIBUTING (issues only), CHANGELOG, CLAUDE.md, `.claude/settings.json` attribution, PR template, dependabot, SHA-pinned CI and security workflows | Files exist; `actionlint` passes; `scripts/ci/test_quality.py` asserts that each workflow pins actions by 40-hex SHA and sets `permissions: contents: read` |
| `quality.py fast` and `full` pass locally and in CI | Exit code 0; the GitHub Actions CI run on the pushed `main` is green |
| The public repo `choscor/choscorusage` exists with `main` pushed | `gh repo view choscor/choscorusage --json visibility` returns `PUBLIC` |
| Discovery finds `~/.claude*`, `~/.codex*`, `$CLAUDE_CONFIG_DIR` and `$CODEX_HOME` candidates without duplicates | `ProfileDiscovery.discover(home:, environment:, keychain:)` unit tests against a temporary directory tree and a fake keychain |
| The Claude keychain service name is derived correctly | `ClaudeKeychainService.name(forConfigDir:)` tests: `nil`/default → `Claude Code-credentials`; `/Users/x/.claude-01` → `Claude Code-credentials-` + the first 8 hex chars of its SHA-256; NFC-equivalent strings give the same result |
| Credentials are read-only and the Keychain is preferred over the file | `ClaudeCredentialReader` tests with a fake keychain and file system. The fake keychain records no write calls, and the code base contains no refresh endpoint. |
| An expired Claude token gives `stale` without a network call | Tests with a fake transport that records zero requests |
| Claude and Codex responses decode into normalized windows; null windows are omitted; unknown fields are tolerated | Decoder tests using JSON fixtures in `Tests/.../Fixtures/` (Claude with all four windows and with nulls; Codex with a 5h/7d pair, with a 30d primary and null secondary, and with `additional_rate_limits`) |
| HTTP 401/403/429/5xx and decode failures map to the specified states; last good data is kept | `UsageRefresher` tests with a fake transport and a fake clock |
| Codex falls back to the newest session log `rate_limits` on network or 5xx failure, but not on 401 | Tests with a fixture `sessions/2026/10/08/*.jsonl` tree |
| API-key Codex profiles show "API key mode – no plan limits" | A test with an `auth.json` fixture whose `auth_mode` is API key |
| The menu bar shows the highest shortest-window %, tinted at 80 and 95, and `—` when there is no data | `MenuBarSummary.make(from:)` unit tests; manual check of the running app |
| A keychain denial stops automatic prompts until the user presses Retry | Tests where a fake keychain returns `errSecUserCanceled`, followed by refresh cycles that make no further keychain reads |
| Notifications fire once per threshold crossing and per reset; deduped across relaunch | `NotificationPolicy` tests that feed a sequence of snapshots and check the emitted events, with dedupe state round-tripped through persistence |
| Refresh interval 1/2/5/10 min (default 5); manual refresh debounced to 10 s | `RefreshScheduler` tests with a fake clock |
| Tokens never appear in logs | The `secrets-policy` gate passes and its Python test proves it catches a violation |
| SwiftLint is pinned and verified, and the Homebrew copy is never used | `quality.py swiftlint-install` exits 0 and is idempotent; `test_quality.py` shows a tampered archive (SHA mismatch) failing and a missing binary producing the install hint |
| The size and complexity limits hold (file 400, function 40, type 250, line 120, complexity 10, nesting 2, params 5) | `quality.py swiftlint` exits 0 on the code base. A test runs the pinned SwiftLint with `.swiftlint.yml` on a synthetic 41-line function and a 401-line file in a temporary directory and expects a failure. |
| Formatting is consistent and doesn't conflict with lint | `quality.py swift-format` and `swiftlint` both pass; running `quality.py format` and then `swiftlint` produces no new findings |
| The layer direction is enforced | The package graph in `Package.swift` is Core ← Providers ← Kit, and the app depends only on Kit. `architecture.py` tests cover a fixture using `URLSession` in Core, `SwiftUI` in Kit, and `Security` in the app, and each one fails. |
| Every public package API is documented, and every file has a purpose header | `swiftlint` (`missing_docs`) passes; `file_headers.py` passes, and its test fails on a file without a header |
| No dead code or unused imports | The `swiftlint-analyze` stage in `full` passes |
| Suppressions are narrow and justified | A test shows a `swiftlint:disable` without a reason, and a file-wide disable, both being rejected |
| The app is menu bar–only, with a working popover, Settings, launch-at-login toggle and notifications | `xcodebuild build test` passes. A manual run with the maintainer's real profiles (7 Claude directories and `~/.codex`) shows each profile's windows, and the result is recorded in the PR Verification section. Offscreen or CI builds are not claimed as visual verification. |

## Constraints and risks

- **Undocumented endpoints.** Both usage endpoints are unofficial, and their shapes may change without notice. Keep each provider's decoder isolated and tolerant, and present an `unsupportedResponse` state rather than crashing. The README must say that the app uses undocumented endpoints and is not affiliated with Anthropic or OpenAI.
- **Keychain friction.** Claude Code's token refresh (about every 8 hours) resets "Always Allow". Users with N profiles may see repeated prompts, which the read-once-per-cycle and stop-after-denial rules limit. A future Developer ID–signed build will have a stable code identity, but the CLI recreating the item still resets the ACL. A Claude statusline cache source was considered and rejected for the MVP. It may come back later if the prompts prove too costly.
- **Token rotation.** Refreshing tokens from the app could log the CLI out. That is why the app never refreshes. The accepted consequence is that idle profiles go stale until the user runs the CLI.
- **Hash rule uncertainty.** The SHA-256 prefix rule was verified for 5 of 6 local profiles. The keychain-item picker handles the remaining cases. Do not try to guess alternative spellings automatically, beyond also trying the absolute path with and without a trailing slash.
- **SwiftLint rule availability.** Rule names and options (for example `closure_body_length`'s options, `private_swiftui_state` and `accessibility_label_for_image`) must exist in the pinned version. If one doesn't, drop it, record that in `docs/CI.md`, and don't substitute a looser limit. The Q10 numbers are fixed: if code doesn't fit, split it rather than raising a limit or suppressing the rule.
- **Strict limits and SwiftUI.** A 40-line function body and a 250-line type body force SwiftUI views to be decomposed into small subviews, such as `ProfileSectionView`, `UsageWindowRow` and `PopoverFooter`. This is intended.
- **No App Sandbox and no Mac App Store.** The app needs to read `~/.claude*` and `~/.codex*` and other apps' keychain items. Distribute it only as a Developer ID app; that work is deferred.
- **Deferred to the later release spec:** Developer ID signing, notarization, the DMG, Sparkle 2 updates, GitHub Releases, the `release-new-version` skill and `docs/MACOS_RELEASE.md`. Follow choscordb's `docs/MACOS_RELEASE.md` and `docs/specs/2026-09-20-macos-production-release.md` then.
  *Superseded (2026-10-09):* [docs/RELEASE.md](../RELEASE.md) covers this work. Releases are a notarized DMG on GitHub Releases with no Sparkle or other auto-update channel, driven by the `release-version` skill.
- **CI runner availability.** If a `macos-26` image with Xcode 26 is unavailable, use the newest macOS image that has the macOS 26 SDK and document the choice in `docs/CI.md`. Do not lower the deployment target.
- **Outward-facing step.** Creating the public repo and pushing are authorized by the maintainer (Q8). Run `quality.py full` locally before the first push. Check that no tokens, fixtures with real data, or personal paths are committed: fixtures must be synthetic, and `.gitignore` covers `.env*`, `*.p12`, `*.pem`, `build/`, `DerivedData/` and `.DS_Store`.
- **Assumptions:**
  - The copyright holder in `LICENSE` is "Choscor"; the maintainer may change it.
  - Notifications are enabled by default.
  - The MVP has no third-party dependencies.

Read this whole spec and inspect the current workspace, including `~/choscor/opensource/choscordb` for the standard files to adapt, before implementing.
