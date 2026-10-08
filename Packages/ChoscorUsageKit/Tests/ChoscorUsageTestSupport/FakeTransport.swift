// Scripted HTTPTransport fake that records every request it receives.
import ChoscorUsageCore
import Foundation
import Synchronization

/// Returns scripted responses keyed by URL host, or throws a transport error.
public final class FakeTransport: HTTPTransport {
    /// A scripted reply.
    public enum Reply: Sendable {
        /// An HTTP response with this status and body.
        case response(Int, Data)
        /// A transport failure such as being offline.
        case offline
    }

    /// Thrown for `.offline` replies.
    public struct Offline: Error {}

    private let state: Mutex<(replies: [String: Reply], requests: [HTTPRequest])>

    /// Creates a transport with replies keyed by host.
    public init(replies: [String: Reply] = [:]) {
        state = Mutex((replies, []))
    }

    /// Requests received so far.
    public var requests: [HTTPRequest] { state.withLock { $0.requests } }

    /// Replaces the reply for `host`.
    public func reply(_ reply: Reply, forHost host: String) {
        state.withLock { $0.replies[host] = reply }
    }

    /// Records `request` and returns its scripted reply (404 when none).
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let reply = state.withLock { state in
            state.requests.append(request)
            return state.replies[request.url.host() ?? ""]
        }
        switch reply {
        case .response(let status, let body): return HTTPResponse(statusCode: status, body: body)
        case .offline: throw Offline()
        case nil: return HTTPResponse(statusCode: 404, body: Data())
        }
    }
}
