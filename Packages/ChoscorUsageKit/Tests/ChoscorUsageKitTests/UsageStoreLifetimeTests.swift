// Tests that the store's automatic refresh timer ends when the store goes away.
import ChoscorUsageCore
import ChoscorUsageProviders
import ChoscorUsageTestSupport
import Foundation
import Testing

@testable import ChoscorUsageKit

@MainActor
struct UsageStoreLifetimeTests {
    @Test func releasingTheStoreCancelsItsRefreshTimer() async throws {
        let home = try TemporaryHome()
        let suite = "ChoscorUsageLifetimeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = ParkedClock()
        var store: UsageStore? = UsageStore(
            dependencies: UsageDependencies(
                fileSystem: LocalFileSystem(homeDirectory: home.path), keychain: FakeKeychain(),
                environment: FakeEnvironment(), clock: clock, providers: [:], notifier: Quiet(),
                preferences: PreferencesStore(defaults: defaults)))
        store?.startAutomaticRefresh()
        await clock.waitUntilParked()
        #expect(clock.cancelledSleeps == 0)
        store = nil
        #expect(clock.cancelledSleeps == 1)
    }
}

private struct Quiet: UsageNotifying {
    func deliver(_: [UsageNotification]) async {}
}
