# Changelog

## Unreleased

- Menu bar–only app showing Claude Code and Codex usage windows for several profiles,
  with the worst shortest-window percentage in the menu bar, tinted at 80% and 95%.
- Automatic discovery of `~/.claude*`, `~/.codex*`, `CLAUDE_CONFIG_DIR` and `CODEX_HOME`
  profiles, confirmed before they are added, plus manual add, rename, reorder and hide.
- Threshold (80%, 95%) and reset notifications, launch at login, and a 1/2/5/10-minute
  refresh interval.
- Codex falls back to its local session logs when the usage endpoint is unavailable.
