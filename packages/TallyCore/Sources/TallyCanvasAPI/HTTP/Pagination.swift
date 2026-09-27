import Foundation

/// Canvas paginates with an RFC 8288 `Link` header. The `next` URL is opaque:
/// it is followed verbatim, never rebuilt (Canvas may use bookmark tokens).
public enum LinkHeader {
    public static func nextURL(in response: HTTPResponse) -> URL? {
        guard let header = response.headers["Link"] else { return nil }
        for link in splitLinks(header) {
            let parts = link.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let target = parts.first, target.hasPrefix("<"), target.hasSuffix(">") else { continue }
            let rels = parts.dropFirst().compactMap(relValues).flatMap { $0 }
            if rels.contains("next") { return URL(string: String(target.dropFirst().dropLast())) }
        }
        return nil
    }

    /// Splits on commas outside `<...>`, since URLs may contain commas.
    private static func splitLinks(_ header: String) -> [String] {
        var links: [String] = [], current = "", inURL = false
        for ch in header {
            switch ch {
            case "<": inURL = true; current.append(ch)
            case ">": inURL = false; current.append(ch)
            case "," where !inURL: links.append(current); current = ""
            default: current.append(ch)
            }
        }
        links.append(current)
        return links
    }

    private static func relValues(_ param: String) -> [String]? {
        let pair = param.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard pair.count == 2, pair[0].lowercased() == "rel" else { return nil }
        let value = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return value.lowercased().split(separator: " ").map(String.init)
    }
}

public enum PageURLError: Error, Sendable, Equatable {
    case notHTTPS, foreignHost, hasCredentials
}

/// A bearer token is only ever attached to a URL on the account's own
/// Canvas hosts over HTTPS (security.md, WP-SEC-08).
public enum PageURLPolicy {
    public static func validate(_ url: URL, allowedHosts: Set<String>) throws(PageURLError) {
        guard url.scheme?.lowercased() == "https" else { throw .notHTTPS }
        guard url.user == nil, url.password == nil else { throw .hasCredentials }
        guard let host = url.host?.lowercased(),
              allowedHosts.contains(where: { $0.lowercased() == host }),
              url.port == nil || url.port == 443 else { throw .foreignHost }
    }
}
