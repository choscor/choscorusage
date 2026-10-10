// Tests reading the newest rate limits from Codex session logs: extreme values and tail reads.
import ChoscorUsageCore
import ChoscorUsageTestSupport
import Foundation
import Testing

@testable import ChoscorUsageProviders

struct CodexSessionLogReaderTests {
    private let home: TemporaryHome
    private let now = Date(timeIntervalSince1970: 1_791_466_800)

    init() throws {
        home = try TemporaryHome()
    }

    private var configDirectory: String { "\(home.path)/.codex" }

    private func tokenCount(_ limits: String, at timestamp: String = "2026-10-08T09:10:00.000Z") -> String {
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","rate_limits":"#
            + limits + "}}"
    }

    @Test func extremeLogValuesDropTheirFieldWithoutTrapping() throws {
        let line = tokenCount(
            #"{"primary":{"used_percent":12,"window_minutes":1e18,"resets_at":1e20},"#
                + #""secondary":{"used_percent":30,"window_minutes":10080,"resets_in_seconds":-1e300}}"#)
        try home.write(".codex/sessions/2026/10/08/rollout-a.jsonl", line + "\n")
        let snapshot = CodexSessionLogReader(fileSystem: LocalFileSystem(homeDirectory: home.path))
            .latestSnapshot(configDirectory: configDirectory, now: now)
        let windows = try #require(snapshot?.windows)
        #expect(windows.map(\.label) == ["primary_window", "7d"])
        #expect(windows.map(\.windowLength) == [nil, .seconds(604_800)])
        #expect(windows.map(\.resetsAt) == [nil, nil])
    }

    /// One synthetic line of about 1 KiB that is not a `token_count` event.
    private var filler: String {
        #"{"timestamp":"2026-10-08T09:00:00.000Z","type":"response_item","payload":{"text":""#
            + String(repeating: "x", count: 1_000) + "\"}}\n"
    }

    @Test func aLargeLogIsReadFromItsTailWithinTheCap() throws {
        let older = tokenCount(#"{"primary":{"used_percent":5,"window_minutes":300}}"#, at: "2026-10-08T08:00:00.000Z")
        let newest = tokenCount(#"{"primary":{"used_percent":42,"window_minutes":300}}"#)
        let body = older + "\n" + String(repeating: filler, count: 6_000) + newest + "\n" + filler
        let path = try home.write(".codex/sessions/2026/10/08/rollout-big.jsonl", body)
        let files = RecordingFileSystem(LocalFileSystem(homeDirectory: home.path))
        let snapshot = CodexSessionLogReader(fileSystem: files).latestSnapshot(
            configDirectory: configDirectory, now: now)
        #expect(snapshot?.windows.map(\.usedPercent) == [42])
        #expect(files.bytesRead(atPath: path) <= 64 * 1_024)
    }

    @Test func aMatchBeyondTheFourMebibyteCapIsNotRead() throws {
        let line = tokenCount(#"{"primary":{"used_percent":5,"window_minutes":300}}"#)
        let body = line + "\n" + String(repeating: filler, count: 6_000)
        let path = try home.write(".codex/sessions/2026/10/08/rollout-big.jsonl", body)
        let files = RecordingFileSystem(LocalFileSystem(homeDirectory: home.path))
        let snapshot = CodexSessionLogReader(fileSystem: files).latestSnapshot(
            configDirectory: configDirectory, now: now)
        #expect(snapshot == nil)
        #expect(files.bytesRead(atPath: path) == 4 * 1_024 * 1_024)
    }

    @Test func aLineSplitAcrossChunksIsReassembled() throws {
        let line = tokenCount(#"{"primary":{"used_percent":17,"window_minutes":300}}"#)
        let padding = String(repeating: "y", count: 64 * 1_024)
        let long = #"{"type":"response_item","payload":{"text":""# + padding + "\"}}\n"
        try home.write(".codex/sessions/2026/10/08/rollout-split.jsonl", line + "\n" + long + long)
        let reader = CodexSessionLogReader(fileSystem: LocalFileSystem(homeDirectory: home.path))
        #expect(reader.latestSnapshot(configDirectory: configDirectory, now: now)?.windows.map(\.usedPercent) == [17])
    }

    @Test func aSymlinkedLogIsReadFromTheEndOfItsTarget() throws {
        let newest = tokenCount(#"{"primary":{"used_percent":64,"window_minutes":300}}"#)
        let target = try home.write("elsewhere/rollout.jsonl", String(repeating: filler, count: 200) + newest + "\n")
        try home.makeDirectory(".codex/sessions/2026/10/08")
        try FileManager.default.createSymbolicLink(
            atPath: "\(configDirectory)/sessions/2026/10/08/rollout-link.jsonl", withDestinationPath: target)
        let reader = CodexSessionLogReader(fileSystem: LocalFileSystem(homeDirectory: home.path))
        #expect(reader.latestSnapshot(configDirectory: configDirectory, now: now)?.windows.map(\.usedPercent) == [64])
    }
}
