import Foundation

public enum HTTPMethod: String, Sendable { case get = "GET", delete = "DELETE", post = "POST" }

/// Header fields with case-insensitive names (RFC 9110 §5.1).
public struct HTTPHeaders: Sendable, Equatable {
    private var fields: [String: String] = [:]
    public init(_ pairs: [String: String] = [:]) {
        for (name, value) in pairs { self[name] = value }
    }
    public subscript(name: String) -> String? {
        get { fields[name.lowercased()] }
        set { fields[name.lowercased()] = newValue }
    }
}

public struct HTTPRequest: Sendable, Equatable {
    public var method: HTTPMethod
    public var url: URL
    public var headers: HTTPHeaders
    public var body: Data?
    public init(method: HTTPMethod = .get, url: URL, headers: HTTPHeaders = HTTPHeaders(), body: Data? = nil) {
        self.method = method; self.url = url; self.headers = headers; self.body = body
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var headers: HTTPHeaders
    public var body: Data
    public init(status: Int, headers: HTTPHeaders = HTTPHeaders(), body: Data = Data()) {
        self.status = status; self.headers = headers; self.body = body
    }
}

/// Failures below HTTP: the request never produced a status code.
public enum TransportError: Error, Sendable, Equatable {
    case offline, timedOut, cancelled, other
}

/// The only way TallyCore talks to the network. `URLSessionTransport` (iOS,
/// ephemeral session, no cache or cookies) and `ReplayTransport` (tests) conform.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse
}
