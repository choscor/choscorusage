// Tests decoding of the undocumented Claude usage response into normalized windows.
import ChoscorUsageCore
import Foundation
import Testing

@testable import ChoscorUsageProviders

struct ClaudeUsageDecoderTests {
    @Test func decodesAllFourKnownWindowsPlusUnknownWindowShapedObjects() throws {
        let windows = try ClaudeUsageDecoder.decode(FixtureLoader.data("claude-usage-all.json"))
        try #require(windows.count == 5)
        #expect(windows.map(\.label) == ["5h", "7d", "7d Opus", "7d Sonnet", "seven_day_oauth_apps"])
        #expect(windows.map(\.usedPercent) == [72, 31, 9.5, 12, 4])
        #expect(
            windows.map(\.windowLength) == [
                .seconds(18_000), .seconds(604_800), .seconds(604_800), .seconds(604_800), nil,
            ])
        #expect(windows[1].resetsAt == Date(timeIntervalSince1970: 1_791_777_600))
        #expect(windows[0].resetsAt.map { Int($0.timeIntervalSince1970) } == 1_791_475_199)
        #expect(windows[3].resetsAt == nil)
    }

    @Test func nullAndMissingWindowsAreOmitted() throws {
        let windows = try ClaudeUsageDecoder.decode(FixtureLoader.data("claude-usage-nulls.json"))
        #expect(windows.map(\.id) == ["five_hour"])
    }

    @Test func aKnownWindowWithNullUtilizationIsOmittedNotFatal() throws {
        let windows = try ClaudeUsageDecoder.decode(FixtureLoader.data("claude-usage-null-utilization.json"))
        #expect(windows.map(\.id) == ["five_hour", "seven_day_opus"])
    }

    @Test func aChangedShapeIsReportedAsAnError() throws {
        #expect(throws: ClaudeUsageDecoder.DecodingFailure.self) {
            try ClaudeUsageDecoder.decode(FixtureLoader.data("claude-usage-changed.json"))
        }
        #expect(throws: ClaudeUsageDecoder.DecodingFailure.self) { try ClaudeUsageDecoder.decode(Data("[]".utf8)) }
    }
}
