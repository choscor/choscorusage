# Fewer Keychain prompts, compact profile rows and crash/leak hardening
- Status: Ready for implementation
- Date: 2026-10-10
- Source: User request in a `/brainstorm` session on 2026-10-10. Evidence: a screenshot of the menu, the
  current code (paths below), a read-only audit of the code for leaks and crashes, the
  [CodexBar Claude notes](https://github.com/steipete/CodexBar/blob/main/docs/claude.md), and
  [Silverfort's write-up on the Claude Code Keychain item](https://www.silverfort.com/blog/skipping-the-lock-a-claude-code-cli-weakness-lets-any-macos-process-read-stored-credentials/).

## Outcome and current state

The user runs six Claude profiles and one Codex profile. They have three problems.

1. **Repeated Keychain prompts.** Each refresh, `ClaudeCredentialReader.read(for:)`
   (`Packages/ChoscorUsageKit/Sources/ChoscorUsageProviders/Claude/ClaudeCredentialReader.swift`)
   reads every Claude Keychain item through `SecItemCopyMatching`
   (`ChoscorUsageProviders/System/SecurityKeychainReader.swift`).
   - About every 8 hours, Claude Code refreshes its token and rewrites its `Claude Code-credentials*` item. That resets the app's "Always Allow" grant, so macOS prompts again for each profile.
   - Claude Code creates the item with `/usr/bin/security`, so the item's access list already trusts that tool. When the same tool reads the item, macOS normally doesn't prompt (Silverfort, above).
2. **The menu rows are too wide.**
   - `ProfileMenuItem.badge` (`ChoscorUsageCore/Policy/ProfileMenuItem.swift`) renders `5h 4% · 4h35m · 7d Fable 0% · 5d3h` and puts `Open Claude Code · ` in front of stale profiles.
   - It also shows unrecognized top-level response objects, such as `iguana_necktie 0% · 26d9h`, using the raw key as the label.
   - `MenuBarSummary.make(from:chosenProfileID:now:)` reuses the badge, so the menu bar has the same problems.
3. **Crash and leak risks.** These were found by the audit and checked against the code; see "Hardening" below.

Desired: no Keychain prompt in normal use, shorter rows in the format below, and those risks removed.

## Decisions and requirements

Decision ledger (all settled by the user in this session):

| ID | Decision | Answer |
| --- | --- | --- |
| Q1 | Keychain read strategy | Read through `/usr/bin/security` and cache the token in memory. Fall back to the direct read only on a user action. |
| Q2 | "Open Claude Code" (stale Claude) | Hide it when windows exist; the tooltip keeps the full message. With no windows, show `Open Claude Code` alone. |
| Q3 | Row format | `5h 4% (4h35m) • 7d Fable 0% (5d3h)` |
| Q4 | Unrecognized Claude windows (`iguana_necktie`) | Always hide. |
| Q5 | Menu bar text | Same as the chosen profile's row badge. It already reuses the badge; the user approved the preview `◔ 5h 0% • 7d Fable 0% (4d14h)`. |
| Q6 | Audit fixes | Fix all four groups: crash on extreme values, Codex log memory, Keychain lock and save race, small cleanups. |

### 1. Keychain: read through the CLI, cache in memory (Q1)

- **New CLI reader.** Add a `KeychainReading` implementation in `ChoscorUsageProviders/System/`, for example `SecurityCLIKeychainReader`.
  - It runs `/usr/bin/security find-generic-password -s <service> -w`, with `-a <account>` when an account is given, and returns stdout minus the trailing newline as `Data`.
  - Run the process through a new Core seam, for example `CommandRunning` in `ChoscorUsageCore/Seams/`, so tests can fake it. The `Process` implementation lives in Providers.
  - Use an absolute executable path and an argument array, never a shell. Never log stdout, stderr or arguments.
  - Map exit statuses to `KeychainError`:
    - 44 (`errSecItemNotFound`) → `nil`.
    - User cancel or deny → `.denied`.
    - Anything else, including a timeout → `.unavailable`.
  - Before relying on the cancel/deny exit codes, check them on the machine and document them with the date verified.
  - Use a bounded timeout so a hung subprocess cannot block forever: long enough for a person to answer a prompt, for example 60 s. Then terminate the process.
  - `serviceNames(withPrefix:)` keeps the existing attribute-only Security query; it never prompts.
- **Fallback.** The existing `SecurityKeychainReader` (direct `SecItemCopyMatching`) is used only when the CLI read fails *and* the fetch came from a user action: `RefreshTrigger.manual` (Refresh Now) or `.retry`. Automatic triggers (`launch`, `timer`, `menuOpened`, `wake`) never use the direct reader.
  - Plumb this through the public seams. For example, `UsageRefresher.refresh(_:allowingPrompt:)` passes a flag to `UsageProviding.fetch`, and `ClaudeCredentialReader.read(for:allowingDirectRead:)` receives it.
  - `UsageStore.refresh(_:)` sets the flag from the trigger; `retry` always sets it.
- **Token cache.**
  - `ClaudeUsageProvider`, or a small actor next to it, keeps the decoded `ClaudeCredentials` in memory only. Never on disk and never in `UserDefaults`.
  - The cache key covers the profile ID, the config directory and the Keychain override.
  - While a cached token is unexpired, a fetch makes **no** Keychain or CLI call.
  - The entry is dropped when:
    - `expiresAt <= now`;
    - the endpoint returns 401 or 403;
    - the profile's directory or override changes, or the profile is removed;
    - the user presses Retry.
  - After a drop, the next fetch reads again: the CLI first, then the direct read on a user action. If the token it reads is still expired, the outcome stays `.stale`, as today.
- **Existing rules still hold.**
  - At most one Keychain item read per profile per refresh cycle.
  - A `.denied` from either reader puts the profile in `keychainDenied`, and automatic refreshes skip it until Retry.
  - The app never writes to the Keychain or calls a refresh endpoint.
- **Mutex.** Keep the direct reader's mutex so prompts don't stack. Because the direct reader now runs only on user action, it no longer ties up cooperative threads during automatic refreshes. Hold no lock across a CLI read.
- **Documentation.** At the CLI reader, document why it works (Claude Code writes the item with `/usr/bin/security`), with the Silverfort and CodexBar links and the date verified. Also update the "Keychain friction" risk in `docs/specs/2026-10-08-choscorusage-menubar-mvp.md` or README if they describe the prompts.

### 2. Row format (Q2–Q5)

- **Window format.** Each window is `<label> <pct>%`, followed by ` (<countdown>)` when `resetsAt` exists. Windows are joined with ` • ` (U+2022 with a space on each side). The countdown keeps `CompactDuration.format` output, including `<1m`.
- **Leading problem.** When a problem leads, it is joined to the windows with ` • ` as well: `Rate limited • 5h 3% (2h)`.
- **Stale Claude.** `.stale(.claude)` contributes no leading text when windows exist. With no windows, the badge is exactly `Open Claude Code`. `ProfileMenuItem.message` (the tooltip) is unchanged.
- **Other problems.** All other problem texts are unchanged, including `.stale(.codex)` → `Sign in again`. This is a non-goal: the user asked only about "Open Claude Code".
- **Empty states.** `Loading…` and `No usage data` are unchanged.
- **Variations to cover** (all approved in the preview):

  ```text
  01 — 5h 4% (4h35m) • 7d Fable 0% (5d3h)
  03 — 5h 0% • 7d Fable 0% (5d17h)              (5h has no resetsAt)
  Default — 5h 0% (<1m) • 7d 53% (2d7h)         (iguana_necktie hidden)
  Default — 30d 53% (25d1h)                     (Codex)
  04 — 5h 0% • 7d Fable 0% (4d14h)              (stale Claude with data)
  04 — Open Claude Code                         (stale Claude, no data)
  02 — Needs Keychain access
  01 — Loading…  /  01 — No usage data
  Menu bar: ◔ 5h 0% • 7d Fable 0% (4d14h)
  ```

- **Unrecognized windows.** `ClaudeUsageDecoder.decode` stops turning unknown top-level window-shaped objects into windows. The `for key in root.keys.sorted()` loop is removed. Known flat keys, all `limits[]` windows (such as `7d Fable`) and `Extra` stay.
  - Update the decoder's doc comment and the test that expects extra windows.
  - Persisted snapshots that already contain such windows get replaced on the next successful fetch; no migration.
- **Menu bar.** The menu bar automatically uses the new badge through `MenuBarSummary`. Nothing in the view computes the format.

### 3. Hardening (Q6)

Each fix needs a test through a public seam that fails before the change.

1. **Extreme dates and values must not crash.**
   - Clamp or reject non-finite or out-of-range values at decode time:
     - `ClaudeLimitsDecoder.resetDate` (epoch `NSNumber`);
     - `CodexLogLine` `resets_at`, `resets_in_seconds` and `window_minutes`;
     - the Codex endpoint decoder.
   - Reset dates outside a sane range become `resetsAt = nil`. A reasonable range is the window from 10 years before to 10 years after the time of decoding; choose a constant and document it.
   - `window_minutes * 60` uses overflow-checked multiplication, and an overflow means no window length.
   - `CompactDuration.format` and `NotificationPolicy`'s notification ID stamp use `Int(exactly:)` or clamping instead of a trapping `Int(Double)`.
   - Decoding a persisted `UsageWindow` re-applies the same 0...100 clamp as `init`, through a custom `init(from:)`.
2. **Codex session logs are read from the tail.**
   - `CodexSessionLogReader.latestSnapshot` must not load whole files. Read backwards in bounded chunks, for example 64 KiB, until a `token_count` line is found or a byte cap is reached, for example 4 MiB per file.
   - Add a ranged-read method to the `FileSystem` seam if needed.
3. **No overlapping saves.** In `UsageStore`, `finishRefresh` and `saveResults` are serialized, for example by chaining like the existing `pendingWrite`. A save that started later always lands last, so older snapshots and ledger state never overwrite newer ones from an overlapping `retry`, `fetchSoon` or `refresh`.
4. **Small cleanups.**
   - Cancel the `labelTicker` loop (`ChoscorUsage/System/AppController.swift`) and the `timer` loop (`UsageStore`) in `deinit`, or with an equivalent ownership change.
   - Remove the NotificationCenter observers when their owner goes away.
   - `NotificationLedger` pruning also drops `armed`, `armedWithoutReset` and `delivered` keys whose window ID is not in the current snapshot.

## Acceptance criteria and public test seams

| Criterion | Observable seam |
| --- | --- |
| An automatic refresh reads a Claude token through the CLI reader and never calls the direct reader | `ClaudeUsageProvider` / `UsageRefresher.refresh` with a fake `CommandRunning` and a recording fake direct `KeychainReading`: zero direct reads on `timer` |
| A cached, unexpired token causes no further Keychain or CLI calls across cycles | Two refresh cycles with `FakeClock` before `expiresAt`: the CLI fake records 1 call |
| Expiry, 401/403, Retry and a changed directory or override each force a re-read | Provider or refresher tests: CLI call count increments after each event |
| CLI failure falls back to the direct read only for `.manual` and `.retry` | `UsageStore.refresh(.manual)` / `retry` with a failing CLI fake: one direct read; `refresh(.timer)`: zero |
| A denial from either reader gates automatic refreshes until Retry | Existing denial tests, extended to the CLI reader's denied exit status |
| CLI exit codes map correctly, and output is trimmed | Unit tests of the CLI reader against a fake `CommandRunning` (44 → nil, cancel → `.denied`, timeout → `.unavailable`) |
| Tokens never appear in logs | `secrets-policy` gate passes; no logging of command output |
| Badge uses `(countdown)` and ` • `, with the variations above | `ProfileMenuItem.make(from:now:).badge` tests for each variation listed |
| Stale Claude hides its problem when windows exist and shows `Open Claude Code` alone otherwise; the tooltip is unchanged | `ProfileMenuItem` tests on `badge` and `message` |
| The menu bar text equals the chosen profile's badge | `MenuBarSummary.make(from:chosenProfileID:now:).text` test |
| Unrecognized top-level Claude objects produce no window | `ClaudeUsageDecoder.decode` test with an `iguana_necktie`-shaped fixture (synthetic) |
| Huge or negative epoch reset values and huge `window_minutes` do not trap | Decoder tests (`ClaudeUsageDecoder`, `CodexLogLine` via `CodexSessionLogReader`, Codex endpoint decoder) plus `CompactDuration.format(1e20)` and a `NotificationPolicy` evaluation with an extreme date |
| A persisted window with an out-of-range percent decodes clamped | `JSONDecoder` round-trip test of `UsageWindow` |
| Codex log reading reads at most the cap per file and still finds the newest line | `CodexSessionLogReader` test with a large synthetic file and a recording `FileSystem` that reports bytes read |
| Overlapping saves keep the newest data | `UsageStore` test with a gated provider: a `retry` overlapping a `refresh`; the persisted snapshots equal the newer result |
| Ledger drops keys for vanished window IDs | `NotificationLedger` / `NotificationPolicy` test |
| Rows look right in the running app | Manual check in a signed debug build (see constraints); say so in the PR's Verification section |

## Constraints and risks

- **Layers.**
  - `CommandRunning` (or whatever the process seam is named) is declared in Core with no `Process` import.
  - The `Process` implementation lives in Providers.
  - Kit plumbs the user-action flag and never imports `Security`.
  - `scripts/ci/architecture.py` must still pass.
- **Process limits.** The app is not sandboxed (`ENABLE_APP_SANDBOX = NO`) and uses the hardened runtime. Spawning `/usr/bin/security` needs no entitlement. Run the subprocess off the main actor.
- **Risk: Anthropic may change how Claude Code writes the item.** If a future Claude Code version stops using `/usr/bin/security` or tightens the item's ACL, the CLI read may prompt (naming "security") or fail. A prompt then counts as a normal denial or success, and a failure falls back to the direct read on user action. The token cache still limits prompts to about once per token lifetime.
- **Risk: CLI output encoding.** `security -w` prints the password as text; non-printable data comes out as hex. Claude's credentials are JSON, so this is expected to be fine. If decoding the trimmed output fails, treat it as `.unavailable`.
- **Privacy.** The token cache stays in memory only. No token, command output or account ID reaches logs, `UserDefaults`, notifications or crash output. Test fixtures are synthetic.
- **Compatibility.** No persisted format changes. Old snapshots with unknown windows or out-of-range values are handled by the decode clamp and replaced on the next successful fetch.
- **Local verification.** Launch builds signed with the developer's Apple Development identity (command-line overrides only, never committed). Avoid needless relaunches, since each one may read Keychain items.
- **Checks.** Run `python3 scripts/ci/quality.py format`, `fast`, and then `full`, because Kit's public API and the app change. Commit with Conventional Commits.
- **Affected areas:**
  - `ChoscorUsageCore/Policy/{ProfileMenuItem,CompactDuration}.swift`
  - `ChoscorUsageCore/Notifications/{NotificationPolicy,NotificationLedger}.swift`
  - `ChoscorUsageCore/Models/UsageWindow.swift`
  - `ChoscorUsageCore/Seams/{UsageProviding,KeychainReading,FileSystem}.swift` and a new process seam
  - `ChoscorUsageProviders/Claude/*`, `ChoscorUsageProviders/Codex/{CodexLogLine,CodexSessionLogReader,CodexUsageDecoder}.swift`, `ChoscorUsageProviders/System/*`
  - `ChoscorUsageKit/{UsageRefresher,UsageStore}.swift`
  - `ChoscorUsage/System/AppController.swift`
  - The matching tests
- **Deferred.** None. Problem labels other than "Open Claude Code" are intentionally unchanged (out of scope per the request).

Read this whole spec and inspect the current workspace before implementing.
