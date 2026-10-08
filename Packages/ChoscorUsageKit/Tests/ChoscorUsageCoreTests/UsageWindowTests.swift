// Tests window-length labels and percentage clamping shared by both providers.
import Foundation
import Testing

@testable import ChoscorUsageCore

struct UsageWindowTests {
    @Test(arguments: [
        (18_000, "5h"), (604_800, "7d"), (2_592_000, "30d"),
        (3_600, "1h"), (43_200, "12h"), (86_400, "1d"), (5_400, "1h30m"), (1_800, "30m"), (1_209_600, "14d"),
    ])
    func labelComesFromTheWindowLength(seconds: Int, label: String) {
        #expect(WindowLabel.short(forSeconds: seconds) == label)
    }

    @Test(arguments: [(18_000, "5 hour"), (604_800, "7 day"), (2_592_000, "30 day"), (5_400, "90 minute")])
    func spokenLabelNamesTheUnit(seconds: Int, spoken: String) {
        #expect(WindowLabel.spoken(forSeconds: seconds) == spoken)
    }

    @Test func usedPercentIsClampedToZeroThroughOneHundred() {
        #expect(
            UsageWindow(id: "a", label: "5h", usedPercent: 140, resetsAt: nil, windowLength: nil).usedPercent == 100)
        #expect(UsageWindow(id: "a", label: "5h", usedPercent: -3, resetsAt: nil, windowLength: nil).usedPercent == 0)
        #expect(
            UsageWindow(id: "a", label: "5h", usedPercent: 42.5, resetsAt: nil, windowLength: nil).usedPercent == 42.5)
    }

    @Test func windowsRoundTripThroughCodable() throws {
        let window = UsageWindow(
            id: "five_hour", label: "5h", usedPercent: 72,
            resetsAt: Date(timeIntervalSince1970: 1_800_000_000), windowLength: .seconds(18_000))
        let data = try JSONEncoder().encode(window)
        #expect(try JSONDecoder().decode(UsageWindow.self, from: data) == window)
    }
}
