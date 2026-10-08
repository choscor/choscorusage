// Tests that the bearer token never follows a redirect to another host.
import ChoscorUsageCore
import Foundation
import Synchronization
import Testing

@testable import ChoscorUsageProviders

@Suite(.serialized)
struct URLSessionTransportTests {
    private let transport = URLSessionTransport(protocolClasses: [RedirectingProtocol.self])

    private func request(_ path: String) throws -> HTTPRequest {
        HTTPRequest(
            url: try #require(URL(string: "https://api.example.test\(path)")),
            headers: ["Authorization": "Bearer secret"])
    }

    @Test func aRedirectToAnotherHostIsNotFollowed() async throws {
        RedirectingProtocol.reset()
        let response = try await transport.send(try request("/to-other-host"))
        #expect(response.statusCode == 302)
        #expect(RedirectingProtocol.hosts == ["api.example.test"])
    }

    @Test func aRedirectWithinTheSameHostIsFollowed() async throws {
        RedirectingProtocol.reset()
        let response = try await transport.send(try request("/to-same-host"))
        #expect(response.statusCode == 200)
        #expect(RedirectingProtocol.hosts == ["api.example.test", "api.example.test"])
    }

    @Test(arguments: [
        ("https://api.example.test/a", "https://API.Example.test:443/b", true),
        ("https://api.example.test/a", "https://api.example.test:8443/b", false),
        ("https://api.example.test/a", "http://api.example.test/b", false),
        ("https://api.example.test/a", "https://elsewhere.example.test/b", false),
    ])
    func originComparisonNormalizesCaseAndDefaultPorts(first: String, second: String, same: Bool) throws {
        let first = try #require(URL(string: first))
        let second = try #require(URL(string: second))
        #expect(URLSessionTransport.isSameOrigin(first, second) == same)
    }

    @Test func hostCaseAndAnExplicitDefaultPortAreTheSameOrigin() async throws {
        RedirectingProtocol.reset()
        let response = try await transport.send(try request("/to-same-origin-spelled-differently"))
        #expect(response.statusCode == 200)
    }
}

/// Serves `/to-other-host` and `/to-same-host` as 302s and everything else as 200, recording
/// which hosts were contacted.
private final class RedirectingProtocol: URLProtocol {
    private static let contacted = Mutex<[String]>([])

    static var hosts: [String] { contacted.withLock { $0 } }

    static func reset() {
        contacted.withLock { $0 = [] }
    }

    override static func canInit(with _: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.contacted.withLock { $0.append(host) }
        let targets = [
            "/to-other-host": "https://elsewhere.example.test/", "/to-same-host": "https://api.example.test/done",
        ]
        if let target = targets[url.path()], let next = URL(string: target),
            let redirect = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target])
        {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: next), redirectResponse: redirect)
            client?.urlProtocol(self, didReceive: redirect, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let success = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])
        if let success {
            client?.urlProtocol(self, didReceive: success, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
