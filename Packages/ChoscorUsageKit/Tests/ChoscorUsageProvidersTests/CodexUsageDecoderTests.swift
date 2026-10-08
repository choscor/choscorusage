// Tests decoding of the private Codex usage response into normalized windows.
import ChoscorUsageCore
import Foundation
import Testing

@testable import ChoscorUsageProviders

struct CodexUsageDecoderTests {
    private let now = Date(timeIntervalSince1970: 1_791_466_800)

    @Test func decodesAFiveHourAndSevenDayPairAndIgnoresUnknownFields() throws {
        let windows = try CodexUsageDecoder.decode(FixtureLoader.data("codex-usage-5h-7d.json"), now: now)
        #expect(windows.map(\.label) == ["5h", "7d"])
        #expect(windows.map(\.usedPercent) == [18, 44])
        #expect(
            windows.map(\.resetsAt) == [
                Date(timeIntervalSince1970: 1_791_480_000), Date(timeIntervalSince1970: 1_791_900_000),
            ])
    }

    @Test func labelsComeFromTheServerLengthAndANullSecondaryIsOmitted() throws {
        let windows = try CodexUsageDecoder.decode(FixtureLoader.data("codex-usage-30d.json"), now: now)
        #expect(windows.map(\.label) == ["30d"])
        #expect(windows.first?.windowLength == .seconds(2_592_000))
        #expect(windows.first?.resetsAt == now.addingTimeInterval(864_000))
    }

    @Test func additionalRateLimitsBecomeNamedWindows() throws {
        let windows = try CodexUsageDecoder.decode(FixtureLoader.data("codex-usage-additional.json"), now: now)
        #expect(windows.map(\.label) == ["5h", "7d", "Spark 5h"])
        #expect(windows.map(\.id) == ["primary_window", "secondary_window", "Spark.primary_window"])
        #expect(windows.last?.usedPercent == 70)
    }

    @Test func aChangedShapeThrows() throws {
        #expect(throws: CodexUsageDecoder.DecodingFailure.self) {
            try CodexUsageDecoder.decode(FixtureLoader.data("codex-usage-changed.json"), now: now)
        }
    }
}
