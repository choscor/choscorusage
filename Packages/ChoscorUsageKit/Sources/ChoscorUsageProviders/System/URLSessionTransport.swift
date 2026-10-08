// URLSession-backed HTTPTransport with no cookies, caching or credential storage.
import ChoscorUsageCore
import Foundation

/// Sends requests with an ephemeral session so tokens never land in a shared cache or cookie jar.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// Creates a transport over a fresh ephemeral session.
    public init() {
        self.init(protocolClasses: nil)
    }

    /// Creates a transport whose session loads through `protocolClasses` (tests stub the network).
    internal init(protocolClasses: [AnyClass]?) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        session = URLSession(configuration: configuration)
    }

    /// Sends a GET request; throws for transport failures, returns any HTTP status. A redirect to
    /// another origin is not followed and comes back as its 3xx status.
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = TimeInterval(request.timeout.components.seconds)
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: urlRequest, delegate: SameOriginRedirects())
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return HTTPResponse(statusCode: http.statusCode, body: data)
    }

    /// Whether two URLs share scheme, host and port, ignoring host case and treating an omitted
    /// port as the scheme's default.
    internal static func isSameOrigin(_ first: URL, _ second: URL) -> Bool {
        func origin(_ url: URL) -> (String?, String?, Int?) {
            let scheme = url.scheme?.lowercased()
            let defaultPort = ["https": 443, "http": 80][scheme ?? ""]
            return (scheme, url.host()?.lowercased(), url.port ?? defaultPort)
        }
        return origin(first) == origin(second)
    }
}

/// Refuses redirects that leave the request's origin, so the bearer token is never sent to a
/// host the user did not configure (e.g. via a redirecting `chatgpt_base_url`).
private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _: URLSession, task: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let origin = task.originalRequest?.url, let target = request.url,
            URLSessionTransport.isSameOrigin(origin, target)
        else {
            return nil
        }
        return request
    }
}
