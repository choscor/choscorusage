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
    /// Session logs grow for as long as a session runs, so files are read backwards in chunks
    /// and never past a per-file cap; the newest `token_count` line is near the end.
    private static let chunkSize = 64 * 1_024
    private static let maximumBytesPerFile = 4 * 1_024 * 1_024
    private static let newline = UInt8(ascii: "\n")
    private static let marker = Data("token_count".utf8)

    private let fileSystem: any FileSystem

    /// Creates a reader over `fileSystem`.
    public init(fileSystem: any FileSystem) {
        self.fileSystem = fileSystem
    }

    /// Returns the newest `token_count` rate limits as a local-log snapshot, scanning at most the
    /// 20 newest session files, each read from its end for at most 4 MiB, and stopping at the
    /// first match. `fetchedAt` is `now`.
    public func latestSnapshot(configDirectory: String, now: Date) -> UsageSnapshot? {
        let directory = ConfigPath.standardized(configDirectory, home: fileSystem.homeDirectory)
        for file in newestFiles(under: "\(directory)/sessions") {
            if let entry = newestEntry(in: file, now: now) {
                let recordedAt = entry.timestamp ?? fileSystem.modificationDate(atPath: file) ?? now
                return UsageSnapshot(windows: entry.windows, fetchedAt: now, source: .localLog(recordedAt: recordedAt))
            }
        }
        return nil
    }

    /// Reads `file` backwards chunk by chunk; the partial line at the start of each chunk is kept
    /// and completed by the chunk before it.
    private func newestEntry(in file: String, now: Date) -> CodexLogLine? {
        var end = fileSystem.fileSize(atPath: file) ?? 0
        var budget = Self.maximumBytesPerFile
        var partial = Data()
        while end > 0, budget > 0 {
            let length = min(Self.chunkSize, end, budget)
            guard let chunk = fileSystem.contents(atPath: file, offset: end - length, length: length) else {
                return nil
            }
            end -= length
            budget -= length
            var lines = (chunk + partial).split(separator: Self.newline, omittingEmptySubsequences: false)
            partial = end > 0 ? Data(lines.removeFirst()) : Data()
            for line in lines.reversed() where line.range(of: Self.marker) != nil {
                if let entry = CodexLogLine.parse(Data(line), now: now) {
                    return entry
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
