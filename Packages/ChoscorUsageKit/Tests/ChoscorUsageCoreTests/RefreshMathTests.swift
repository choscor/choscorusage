// Tests refresh-interval choices and the capped exponential 429 backoff.
import Testing

@testable import ChoscorUsageCore

struct RefreshMathTests {
    @Test func intervalChoicesAreOneTwoFiveAndTenMinutesDefaultingToFive() {
        #expect(
            RefreshInterval.allCases.map(\.duration) == [.seconds(60), .seconds(120), .seconds(300), .seconds(600)])
        #expect(RefreshInterval.default.duration == .seconds(300))
    }

    @Test(arguments: [(1, 60), (2, 120), (3, 240), (5, 960), (6, 1_800), (20, 1_800)])
    func rateLimitBackoffDoublesFromOneMinuteUpToThirtyMinutes(attempt: Int, seconds: Int) {
        #expect(RateLimitBackoff.delay(afterConsecutiveRateLimits: attempt) == .seconds(seconds))
    }
}
