// Tests the compact countdown and age text shown in the menu.
import Testing

@testable import ChoscorUsageCore

struct CompactDurationTests {
    @Test(arguments: [
        (4_320.0, "1h12m"), (273_600, "3d4h"), (432_000, "5d"), (2_700, "45m"), (13_200, "3h40m"),
        (3_600, "1h"), (59, "<1m"), (0, "<1m"), (-30, "<1m"),
    ])
    func countdownUsesTheTwoLargestUnits(seconds: Double, text: String) {
        #expect(CompactDuration.format(seconds) == text)
    }

    @Test(arguments: [
        (1e20, "106751991167300d15h"), (.infinity, "106751991167300d15h"), (-1e20, "<1m"), (.nan, "<1m"),
    ])
    func countdownClampsValuesBeyondTheIntegerRange(seconds: Double, text: String) {
        #expect(CompactDuration.format(seconds) == text)
    }

    @Test(arguments: [(20.0, "just now"), (60, "1m ago"), (3_700, "1h1m ago"), (90_000, "1d1h ago")])
    func ageReadsAsElapsedTime(seconds: Double, text: String) {
        #expect(CompactDuration.age(seconds) == text)
    }
}
