// The injectable dependencies of UsageStore, plus the live wiring used by the app.
import ChoscorUsageCore
import ChoscorUsageProviders
import Foundation

/// Everything the store touches outside memory. Tests pass fakes; the app uses ``live(appVersion:notifier:)``.
public struct UsageDependencies: Sendable {
    /// Files: credentials and logs (read-only) and Application Support (read-write).
    public var fileSystem: any FileSystem
    /// Read-only Keychain access for discovery and the Claude Keychain-item picker.
    public var keychain: any KeychainReading
    /// Process environment for `CLAUDE_CONFIG_DIR` and `CODEX_HOME`.
    public var environment: any EnvironmentReading
    /// Time source and sleeps.
    public var clock: any WallClock
    /// One fetcher per provider.
    public var providers: [Provider: any UsageProviding]
    /// Notification delivery.
    public var notifier: any UsageNotifying
    /// UserDefaults-backed preferences.
    public var preferences: PreferencesStore
    /// Shortest time between two fetches of one profile, per provider; none unless set.
    public var minimumFetchSpacing: [Provider: Duration] = [:]

    /// Creates dependencies from explicit parts.
    public init(
        fileSystem: any FileSystem, keychain: any KeychainReading, environment: any EnvironmentReading,
        clock: any WallClock, providers: [Provider: any UsageProviding], notifier: any UsageNotifying,
        preferences: PreferencesStore
    ) {
        self.fileSystem = fileSystem
        self.keychain = keychain
        self.environment = environment
        self.clock = clock
        self.providers = providers
        self.notifier = notifier
        self.preferences = preferences
    }

    /// The real system: URLSession, the Security Keychain, the user's home and `UserDefaults.standard`.
    /// Claude tokens are read through `/usr/bin/security`; the in-process Keychain read is only
    /// its fallback on a user action, plus attribute-only listing and Codex's keyring item.
    public static func live(appVersion: String, notifier: any UsageNotifying) -> Self {
        let fileSystem = LocalFileSystem()
        let keychain = SecurityKeychainReader()
        let cliKeychain = SecurityCLIKeychainReader(runner: ProcessCommandRunner(), attributes: keychain)
        let transport = URLSessionTransport()
        let clock = SystemClock()
        let userAgent = "ChoscorUsage/\(appVersion)"
        let claude = ClaudeUsageProvider(
            credentials: ClaudeCredentialReader(
                keychain: cliKeychain, directKeychain: keychain, fileSystem: fileSystem),
            transport: transport, clock: clock, userAgent: userAgent)
        let codex = CodexUsageProvider(
            fileSystem: fileSystem, keychain: keychain, transport: transport, clock: clock, userAgent: userAgent)
        var dependencies = Self(
            fileSystem: fileSystem, keychain: keychain, environment: ProcessEnvironment(), clock: clock,
            providers: [.claude: claude, .codex: codex], notifier: notifier,
            preferences: PreferencesStore(defaults: .standard))
        dependencies.minimumFetchSpacing = FetchSpacing.live
        return dependencies
    }
}
