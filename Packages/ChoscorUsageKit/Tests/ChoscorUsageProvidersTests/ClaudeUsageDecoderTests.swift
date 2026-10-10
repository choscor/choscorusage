// Tests decoding of the undocumented Claude usage response into normalized windows.
import ChoscorUsageCore
import Foundation
import Testing

@testable import ChoscorUsageProviders

struct ClaudeUsageDecoderTests {
    private let now = Date(timeIntervalSince1970: 1_791_466_800)

    @Test func decodesAllFourKnownWindowsAndIgnoresUnknownWindowShapedObjects() throws {
        let windows = try ClaudeUsageDecoder.decode(FixtureLoader.data("claude-usage-all.json"), now: now)
        try #require(windows.count == 4)
        #expect(windows.map(\.label) == ["5h", "7d", "7d Opus", "7d Sonnet"])
        #expect(windows.map(\.usedPercent) == [72, 31, 9.5, 12])
        #expect(
            windows.map(\.windowLength) == [
                .seconds(18_000), .seconds(604_800), .seconds(604_800), .seconds(604_800),
            ])
        #expect(windows[1].resetsAt == Date(timeIntervalSince1970: 1_791_777_600))
        #expect(windows[0].resetsAt.map { Int($0.timeIntervalSince1970) } == 1_791_475_199)
        #expect(windows[3].resetsAt == nil)
    }

    @Test func anUnrecognizedTopLevelObjectProducesNoWindow() throws {
        let body = #"""
            {"five_hour":{"utilization":3,"resets_at":"2026-10-10T12:00:00Z"},
             "iguana_necktie":{"utilization":0,"resets_at":"2026-11-05T09:00:00Z"}}
            """#
        let windows = try ClaudeUsageDecoder.decode(Data(body.utf8), now: now)
        #expect(windows.map(\.id) == ["five_hour"])
    }

    @Test func nullAndMissingWindowsAreOmitted() throws {
        let windows = try ClaudeUsageDecoder.decode(FixtureLoader.data("claude-usage-nulls.json"), now: now)
        #expect(windows.map(\.id) == ["five_hour"])
    }

    @Test func aKnownWindowWithNullUtilizationIsOmittedNotFatal() throws {
        let windows = try ClaudeUsageDecoder.decode(
            FixtureLoader.data("claude-usage-null-utilization.json"), now: now)
        #expect(windows.map(\.id) == ["five_hour", "seven_day_opus"])
    }

    @Test func aChangedShapeIsReportedAsAnError() throws {
        #expect(throws: ClaudeUsageDecoder.DecodingFailure.self) {
            try ClaudeUsageDecoder.decode(FixtureLoader.data("claude-usage-changed.json"), now: now)
        }
        #expect(throws: ClaudeUsageDecoder.DecodingFailure.self) {
            try ClaudeUsageDecoder.decode(Data("[]".utf8), now: now)
        }
    }

    @Test func theLimitsArrayWinsOverFlatKeysAndKeepsTheFixedOrder() throws {
        let windows = try ClaudeUsageDecoder.decode(FixtureLoader.data("claude-usage-limits.json"), now: now)
        #expect(
            windows.map(\.id) == ["five_hour", "seven_day", "seven_day_fable", "limits.daily_burst", "extra_usage"])
        #expect(windows.map(\.label) == ["5h", "7d", "7d Fable", "daily_burst", "Extra"])
        #expect(windows.map(\.usedPercent) == [41, 21, 63, 7, 25])
        #expect(windows.map(\.windowLength) == [.seconds(18_000), .seconds(604_800), .seconds(604_800), nil, nil])
        #expect(windows[1].resetsAt == Date(timeIntervalSince1970: 1_791_763_200))
        #expect(windows[2].resetsAt == Date(timeIntervalSince1970: 1_791_763_200))
        #expect(windows[4].resetsAt == nil)
    }

    @Test func extraUsageIsShownOnlyWhenEnabled() throws {
        let body = #"{"five_hour":null,"extra_usage":{"is_enabled":false,"utilization":90}}"#
        #expect(try ClaudeUsageDecoder.decode(Data(body.utf8), now: now).isEmpty)
    }

    @Test func resetTimesFarFromNowAreDroppedInsteadOfKept() throws {
        let body = #"""
            {"five_hour":{"utilization":3,"resets_at":"9999-12-31T00:00:00Z"},
             "limits":[{"kind":"weekly_all","percent":5,"resets_at":1e20},
                       {"kind":"weekly_scoped","percent":6,"resets_at":-1e20,
                        "scope":{"model":{"display_name":"Fable"}}},
                       {"kind":"daily_burst","percent":7,"resets_at":1791500000}]}
            """#
        let windows = try ClaudeUsageDecoder.decode(Data(body.utf8), now: now)
        #expect(windows.map(\.id) == ["five_hour", "seven_day", "seven_day_fable", "limits.daily_burst"])
        #expect(windows.map(\.resetsAt) == [nil, nil, nil, Date(timeIntervalSince1970: 1_791_500_000)])
    }
}
