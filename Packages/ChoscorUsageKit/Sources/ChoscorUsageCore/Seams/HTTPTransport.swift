// The injectable HTTP seam: value-type requests and responses plus the sending protocol.
import Foundation

/// A GET request described without URLSession types.
public struct HTTPRequest: Equatable, Sendable {
    /// Absolute request URL.
    public let url: URL
    /// Header fields; values may be secret and must never be logged.
    public let headers: [String: String]
    /// Maximum time to wait for the whole response.
    public let timeout: Duration

    /// Creates a request with the app's 15-second default timeout.
    public init(url: URL, headers: [String: String], timeout: Duration = .seconds(15)) {
        self.url = url
        self.headers = headers
        self.timeout = timeout
    }
}

/// A received HTTP response.
public struct HTTPResponse: Equatable, Sendable {
    /// HTTP status code.
    public let statusCode: Int
    /// Raw body; never logged or persisted.
    public let body: Data

    /// Creates a response.
    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// Sends HTTP requests. Implementations run off the main actor.
public protocol HTTPTransport: Sendable {
    /// Sends `request`. Throws only for transport failures (offline, timeout, TLS); any HTTP
    /// status, including 4xx and 5xx, is returned as a response.
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}
