// Reads the newest rate-limit snapshot Codex wrote to its local session logs.
import ChoscorUsageCore
import Foundation

/// Fallback source for Codex usage when the endpoint is unreachable or unreadable.
///
/// Codex appends `event_msg` lines whose `payload.type` is `token_count` to
/// `<config-dir>/sessions/YYYY/MM/DD/rollout-*.jsonl`; `payload.rate_limits.primary`/`secondary` are
/// `{used_percent, window_minutes, resets_at (epoch seconds)}` or `null` (openai/codex
/// `RateLimitSnapshot`, verified 2026-10-08).
public struct CodexSessionLogReader: Sendable {
    private static let maximumFiles = 20

    private let fileSystem: any FileSystem

    /// Creates a reader over `fileSystem`.
    public init(fileSystem: any FileSystem) {
        self.fileSystem = fileSystem
    }

    /// Returns the newest `token_count` rate limits as a local-log snapshot, scanning at most the
    /// 20 newest session files and stopping at the first match. `fetchedAt` is `now`.
    public func latestSnapshot(configDirectory: String, now: Date) -> UsageSnapshot? {
        let directory = ConfigPath.standardized(configDirectory, home: fileSystem.homeDirectory)
        let files = newestFiles(under: "\(directory)/sessions")
        for file in files {
            guard let data = fileSystem.contents(atPath: file), let text = String(bytes: data, encoding: .utf8) else {
                continue
            }
            let lines = text.split(whereSeparator: \.isNewline)
            for line in lines.reversed() where line.contains("token_count") {
                if let entry = CodexLogLine.parse(Data(line.utf8)) {
                    let recordedAt = entry.timestamp ?? fileSystem.modificationDate(atPath: file) ?? now
                    return UsageSnapshot(
                        windows: entry.windows, fetchedAt: now, source: .localLog(recordedAt: recordedAt))
                }
            }
        }
        return nil
    }

    /// Walks dated directories newest-name-first, keeps the newest 20 `.jsonl` files, then orders
    /// them by modification date so a long-running older session still counts as newest.
    private func newestFiles(under root: String) -> [String] {
        var found: [String] = []
        var pending = [root]
        while let directory = pending.popLast(), found.count < Self.maximumFiles {
            let entries = fileSystem.directoryEntries(atPath: directory).sorted()
            for name in entries {
                let path = "\(directory)/\(name)"
                if fileSystem.isDirectory(atPath: path) {
                    pending.append(path)
                }
            }
            let logs = entries.filter { $0.hasSuffix(".jsonl") }.reversed().map { "\(directory)/\($0)" }
            found += logs.prefix(Self.maximumFiles - found.count)
        }
        return found.sorted {
            (fileSystem.modificationDate(atPath: $0) ?? .distantPast)
                > (fileSystem.modificationDate(atPath: $1) ?? .distantPast)
        }
    }
}
