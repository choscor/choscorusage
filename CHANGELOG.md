# Changelog

## Unreleased

## [0.1.1] - 2026-10-10

### Improvements

- ChoscorUsage reads each Claude Code token through the macOS `security` tool. Usually, macOS does not show a Keychain prompt again after Claude Code renews the token.
- ChoscorUsage keeps each Claude Code token in memory until it expires or the usage service rejects it. Retry reads the token again.
- Automatic refreshes do not read the Keychain directly. If a Claude Code profile needs Keychain access, click Refresh Now or Retry.
- Profile rows are shorter. Each window shows its reset time in parentheses, for example `5h 4% (4h35m)`. A bullet (•) separates the windows.
- An expired Claude token does not show at the start of a row that has usage windows. The tooltip shows the full message.
- ChoscorUsage reads at most 4 MiB from the end of each Codex session log. This uses less memory for large logs.

### Fixes

- Claude Code profiles do not show windows that have only an internal name.
- ChoscorUsage ignores reset times more than ten years from now. Incorrect reset times and countdowns do not stop the app.
- When one Codex value is out of range, ChoscorUsage ignores only that value. The other windows in the response show correctly.
- An automatic refresh does not replace newer results from a Retry.
- ChoscorUsage removes the alert history of a window when the usage service does not report that window again.

## [0.1.0] - 2026-10-09

### Features

- The menu bar shows the highest percentage of the shortest usage window of all visible profiles.
  The color of the value changes at 80% and 95%.
- Click a profile row to show the usage of that profile in the menu bar. Click the row again to
  show the highest percentage again.
- The menu bar item opens a standard macOS menu. Each visible profile has one row with its
  Claude Code or Codex logo, its name and its usage windows.
- Each usage window shows its percentage and the time until it resets, for example `5h 72% · 1h12m`.
- The menu also contains Add Profile…, Scan for Profiles…, Refresh Now, Settings… and
  Quit ChoscorUsage. Refresh Now, Settings… and Quit ChoscorUsage have keyboard shortcuts.
- ChoscorUsage finds Claude Code and Codex profiles in `~/.claude*`, `~/.codex*`,
  `CLAUDE_CONFIG_DIR` and `CODEX_HOME`. You confirm each profile before ChoscorUsage adds it.
- Add Profile… opens a folder picker. ChoscorUsage identifies the folder as a Claude Code or
  a Codex configuration folder.
- In Settings, you can rename, reorder, hide and remove profiles. You can also select the
  Keychain item for a Claude Code profile.
- You can set the refresh interval to 1, 2, 5 or 10 minutes. ChoscorUsage can start at login.
- ChoscorUsage sends a notification at 80% and 95% usage and when a usage window resets.
  It does not send the same notification again after a restart.
- Claude Code profiles show the weekly limit of each model, for example `7d Fable`. They show an
  Extra window when extra usage is on.
- When the Codex usage service is not available, ChoscorUsage reads the usage from the local
  Codex session logs. This also works with the logs of older Codex versions.
- ChoscorUsage reads the Codex login from the Keychain when `auth.json` is absent.
- ChoscorUsage only reads the CLI credentials. It does not renew tokens and does not write to
  the Keychain.
- When a Claude access token expires, the menu shows Open Claude Code. Open Claude Code with
  that profile to get a new token.
- If macOS does not give Keychain access, ChoscorUsage stops automatic refreshes for that
  profile until you click Retry.
- ChoscorUsage gets the usage of each Claude Code profile not more than one time in three
  minutes. Retry gets the usage immediately.
- When you open the menu, ChoscorUsage refreshes data that is older than 60 seconds.
- ChoscorUsage has a gauge app icon.
