import Foundation

public enum InstitutionHostError: Error, Sendable, Equatable {
    case empty, invalid, notAllowed
}

/// Normalises what a student types ("https://Canvas.School.edu/login") into a
/// bare lowercase host. Tokens only ever go to this host over HTTPS.
public enum InstitutionHost {
    public static func normalize(_ input: String) throws(InstitutionHostError) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { throw .empty }
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        if let cut = text.firstIndex(where: { "/?#".contains($0) }) { text = String(text[..<cut]) }
        if text.hasSuffix(".") { text.removeLast() }
        // ASCII letters, digits, hyphens and dots only; IDN input is rejected
        // until punycode conversion is verified (UNVERIFIED on Linux Foundation).
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard text.allSatisfy(allowed.contains) else { throw .invalid }
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && $0.first != "-" && $0.last != "-" }),
              text.count <= 253,
              let lastLabel = labels.last // always present: `labels.count >= 2` above
        else { throw .invalid }
        guard !lastLabel.allSatisfy(\.isNumber), text != "localhost" else { throw .notAllowed }
        return text
    }
}
