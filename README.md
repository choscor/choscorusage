# ChoscorUsage

A macOS menu bar app that shows how close your Claude Code and Codex CLI accounts are
to their usage limits (the 5-hour, 7-day and any other windows), and when each window
resets. It tracks any number of profiles side by side. Licensed under the MIT License.

- Lives only in the menu bar: a gauge and the highest percentage across your profiles,
  orange from 80% and red from 95%.
- The popover lists every visible profile with all of its windows and reset countdowns.
- Discovers `~/.claude*` and `~/.codex*` config directories, plus `CLAUDE_CONFIG_DIR`
  and `CODEX_HOME`, and asks before adding them.
- Optional alerts when a window crosses 80% or 95% and when it resets; launch at login.

> **Unofficial.** ChoscorUsage reads usage from undocumented endpoints
> (`api.anthropic.com/api/oauth/usage` and `chatgpt.com/backend-api/wham/usage`) that may
> change without notice. It is not affiliated with, endorsed by, or supported by Anthropic
> or OpenAI.

## Privacy and credentials

ChoscorUsage reuses each CLI's existing sign-in **read-only**. It never refreshes tokens
and never writes to the Keychain or to any file in a CLI config directory, so it cannot
sign you out of a CLI. When a token expires, the profile shows as stale until you run
`claude` or `codex login` in that profile. Tokens, account IDs and response bodies are
never logged or stored. macOS may ask once per Claude profile for Keychain access; if you
deny it, the app stops asking until you press **Retry**.

## Downloads

There are no binary releases yet. Signed and notarized builds with automatic updates are
planned; until then, build from source (see [docs/BUILD.md](docs/BUILD.md)). Requires
macOS 26 or later on Apple Silicon.

## Development

Install Xcode 26, Python 3.12+, actionlint 1.7.7 and the pinned Python tools, then use the
repository-owned quality interface:

```sh
python -m pip install -r scripts/ci/requirements.txt
python scripts/ci/quality.py swiftlint-install
python scripts/ci/quality.py fast
python scripts/ci/quality.py full
```

`fast` runs swift-format, SwiftLint, the architecture, file-header and secrets policies,
Ruff and the Python tests, actionlint, and the package tests. `full` adds
`xcodebuild build test` and `swiftlint analyze`. Every gate is also a focused stage; run
`python scripts/ci/quality.py --help` and see [docs/CI.md](docs/CI.md). Contribution policy
is in [CONTRIBUTING.md](CONTRIBUTING.md).

## Architecture

The app target is a thin SwiftUI shell (`MenuBarExtra`, Settings, notifications, login
item). All behavior lives in the local Swift package `Packages/ChoscorUsageKit`, layered
`ChoscorUsageCore` ← `ChoscorUsageProviders` ← `ChoscorUsageKit`:

- **Core** holds models and pure policy (window labels, menu bar summary, notification
  rules, backoff) and the protocols for every external effect.
- **Providers** reads credentials, calls and decodes each endpoint, parses Codex session
  logs, discovers profiles, and implements the protocols with URLSession, Security and
  FileManager.
- **Kit** orchestrates refreshes, persistence and preferences for the app.

The compiler enforces the direction, and `scripts/ci/architecture.py` bans specific APIs
per layer. See [CLAUDE.md](CLAUDE.md) for the full table.
