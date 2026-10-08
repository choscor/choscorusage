// Tests refresh triggers: interval timer, manual debounce, popover staleness and wake.
import ChoscorUsageCore
import ChoscorUsageTestSupport
import Synchronization
import Testing

@testable import ChoscorUsageKit

struct RefreshSchedulerTests {
    private let clock = FakeClock()

    private func begin(_ scheduler: inout RefreshScheduler, _ trigger: RefreshTrigger) -> Bool {
        scheduler.begin(trigger, now: clock.now)
    }

    @Test func defaultsToFiveMinutes() {
        #expect(RefreshScheduler().interval == .fiveMinutes)
    }

    @Test func manualRefreshIsDebouncedToOncePerTenSeconds() {
        var scheduler = RefreshScheduler()
        #expect(begin(&scheduler, .manual))
        clock.advance(by: .seconds(9))
        #expect(!begin(&scheduler, .manual))
        clock.advance(by: .seconds(1))
        #expect(begin(&scheduler, .manual))
    }

    @Test func openingThePopoverRefreshesOnlyDataOlderThanSixtySeconds() {
        var scheduler = RefreshScheduler()
        #expect(begin(&scheduler, .popoverOpened))
        clock.advance(by: .seconds(60))
        #expect(!begin(&scheduler, .popoverOpened))
        clock.advance(by: .seconds(1))
        #expect(begin(&scheduler, .popoverOpened))
    }

    @Test func wakeTimerLaunchAndRetryAlwaysRefresh() {
        var scheduler = RefreshScheduler()
        for trigger in [RefreshTrigger.launch, .timer, .wake, .retry] {
            #expect(begin(&scheduler, trigger))
        }
    }

    @Test(arguments: RefreshInterval.allCases)
    func timerTicksOncePerChosenInterval(interval: RefreshInterval) async {
        let ticks = Mutex(0)
        let task = Task {
            await RefreshScheduler.runTimer(
                clock: clock, interval: { interval },
                tick: {
                    let count = ticks.withLock { count in
                        count += 1
                        return count
                    }
                    if count == 3 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                })
        }
        await task.value
        #expect(ticks.withLock { $0 } == 3)
        #expect(clock.sleeps == Array(repeating: interval.duration, count: 3))
    }
}
