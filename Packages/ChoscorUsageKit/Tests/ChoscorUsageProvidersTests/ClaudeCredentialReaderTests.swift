// Tests that Claude credentials come from the Keychain first, then the file, read-only.
import ChoscorUsageCore
import ChoscorUsageTestSupport
import Foundation
import Testing

@testable import ChoscorUsageProviders

struct ClaudeCredentialReaderTests {
    private let home: TemporaryHome
    private let files: RecordingFileSystem
    private let keychain = FakeKeychain()
    private let direct = FakeKeychain()

    init() throws {
        home = try TemporaryHome()
        files = RecordingFileSystem(LocalFileSystem(homeDirectory: home.path))
    }

    private func payload(_ token: String, expiresAtMillis: Int64 = 1_900_000_000_000) -> Data {
        Data(#"{"claudeAiOauth":{"accessToken":"\#(token)","refreshToken":"r","expiresAt":\#(expiresAtMillis)}}"#.utf8)
    }

    private func json(_ token: String) -> String {
        #"{"claudeAiOauth":{"accessToken":"\#(token)","expiresAt":1900000000000}}"#
    }

    private func profile(_ directory: String, override: String? = nil) -> Profile {
        Profile(
            provider: .claude, configDirectory: "\(home.path)/\(directory)", displayName: "P", order: 0,
            keychainServiceOverride: override)
    }

    private var reader: ClaudeCredentialReader {
        ClaudeCredentialReader(keychain: keychain, directKeychain: direct, fileSystem: files)
    }

    @Test func keychainWinsOverTheCredentialsFile() throws {
        let work = profile(".claude-work")
        keychain.set(ClaudeKeychainService.name(forConfigDir: work.configDirectory), .success(payload("from-keychain")))
        try home.write(".claude-work/.credentials.json", json("from-file"))
        let result = reader.read(for: work, allowingDirectRead: false)
        #expect(
            result
                == .found(
                    ClaudeCredentials(
                        accessToken: "from-keychain", expiresAt: Date(timeIntervalSince1970: 1_900_000_000))))
    }

    @Test func fallsBackToTheCredentialsFileWhenNoKeychainItemExists() throws {
        try home.write(".claude-work/.credentials.json", json("from-file"))
        #expect(reader.read(for: profile(".claude-work"), allowingDirectRead: false).accessToken == "from-file")
    }

    @Test func aLockedKeychainIsReportedUnlessTheCredentialsFileHasAToken() throws {
        let work = profile(".claude-work")
        keychain.set(
            ClaudeKeychainService.name(forConfigDir: work.configDirectory),
            .failure(.unavailable(status: -25_308)))
        #expect(reader.read(for: work, allowingDirectRead: false) == .keychainUnavailable)
        try home.write(".claude-work/.credentials.json", json("from-file"))
        #expect(reader.read(for: work, allowingDirectRead: false).accessToken == "from-file")
    }

    @Test func defaultProfileReadsTheUnsuffixedService() {
        keychain.set("Claude Code-credentials", .success(payload("default")))
        let result = reader.read(for: profile(".claude"), allowingDirectRead: false)
        #expect(result.accessToken == "default")
        #expect(keychain.reads == ["Claude Code-credentials"])
    }

    @Test func userPickedOverrideIsTheOnlyServiceRead() {
        keychain.set("Claude Code-credentials-picked", .success(payload("picked")))
        let picked = profile(".claude-personal", override: "Claude Code-credentials-picked")
        let result = reader.read(for: picked, allowingDirectRead: false)
        #expect(result.accessToken == "picked")
        #expect(keychain.reads == ["Claude Code-credentials-picked"])
    }

    @Test func deniedKeychainStopsWithoutTryingOtherSourcesOrPrompts() throws {
        let work = profile(".claude-work")
        keychain.set(ClaudeKeychainService.name(forConfigDir: work.configDirectory), .failure(.denied))
        try home.write(".claude-work/.credentials.json", json("file"))
        #expect(reader.read(for: work, allowingDirectRead: false) == .keychainDenied)
        #expect(keychain.reads.count == 1)
    }

    @Test func aFailedFirstReadFallsBackToTheDirectReadOnlyWhenAllowed() {
        let work = profile(".claude-work")
        let service = ClaudeKeychainService.name(forConfigDir: work.configDirectory)
        keychain.set(service, .failure(.unavailable(status: 36)))
        direct.set(service, .success(payload("direct")))
        #expect(reader.read(for: work, allowingDirectRead: false) == .keychainUnavailable)
        #expect(direct.reads.isEmpty)
        #expect(reader.read(for: work, allowingDirectRead: true).accessToken == "direct")
        #expect(direct.reads == [service])
    }

    @Test func undecodableFirstReadOutputCountsAsAFailedRead() {
        let work = profile(".claude-work")
        let service = ClaudeKeychainService.name(forConfigDir: work.configDirectory)
        keychain.set(service, .success(Data("7b2263".utf8)))
        direct.set(service, .success(payload("direct")))
        #expect(reader.read(for: work, allowingDirectRead: false) == .keychainUnavailable)
        #expect(reader.read(for: work, allowingDirectRead: true).accessToken == "direct")
    }

    @Test func aSuccessfulOrMissingFirstReadNeverTouchesTheDirectReader() {
        let work = profile(".claude-work")
        let service = ClaudeKeychainService.name(forConfigDir: work.configDirectory)
        direct.set(service, .success(payload("direct")))
        #expect(reader.read(for: work, allowingDirectRead: true) == .notFound)
        keychain.set(service, .success(payload("cli")))
        #expect(reader.read(for: work, allowingDirectRead: true).accessToken == "cli")
        #expect(direct.reads.isEmpty)
    }

    @Test func aDirectReadDenialIsADenial() throws {
        let work = profile(".claude-work")
        let service = ClaudeKeychainService.name(forConfigDir: work.configDirectory)
        keychain.set(service, .failure(.unavailable(status: 1)))
        direct.set(service, .failure(.denied))
        try home.write(".claude-work/.credentials.json", json("file"))
        #expect(reader.read(for: work, allowingDirectRead: true) == .keychainDenied)
    }

    @Test func missingEverywhereIsReportedAsNotFound() {
        #expect(reader.read(for: profile(".claude-empty"), allowingDirectRead: false) == .notFound)
    }

    @Test func readingNeverWritesFilesAndTheCodeHasNoRefreshEndpoint() throws {
        try home.write(".claude-work/.credentials.json", json("file"))
        _ = reader.read(for: profile(".claude-work"), allowingDirectRead: false)
        #expect(files.writtenPaths.isEmpty)
        let sources = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources")
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        let swiftFiles = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        #expect(!swiftFiles.isEmpty)
        for file in swiftFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("oauth/token"), "\(file.lastPathComponent) mentions a token endpoint")
            #expect(!text.contains("grant_type"), "\(file.lastPathComponent) builds a refresh grant")
        }
    }
}
