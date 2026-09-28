import Foundation
import Testing

/// M3-A's two source rules, checked on every CI run over the shipping sources (the hosted tests read
/// the repository the same way `TallyTestSupport.Fixtures` does, through `#filePath`):
/// - UX-WP-19: no emoji in UI strings (VoiceOver reads an emoji aloud literally; ux-ui.md UX-16);
/// - UX-WP-15: no `Int.random` anywhere in shipping code, and no randomness at all in app code (the
///   old mockup's random grade distribution, UX-12, changed on every render).
@Suite("M3-A: source hygiene (no emoji in UI strings, no random values)")
struct ScreenSourceHygieneTests {
    /// `<repo>/apps/TallyiOS/TallyAppTests/ScreenSourceHygieneTests.swift` → `<repo>`.
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The app's shipping code: every UI string lives here.
    static let appRoots = ["packages/TallyAppleKit/Sources", "apps/TallyiOS/Tally", "apps/TallyiOS/TallyWidgets"]
    /// TallyCore's shipping code (its test support is not shipping code).
    static let coreRoot = "packages/TallyCore/Sources"
    static let coreExcluded = "packages/TallyCore/Sources/TallyTestSupport"

    static func swiftFiles(under root: String, excluding excluded: String? = nil) throws -> [URL] {
        let base = repository.appendingPathComponent(root)
        guard FileManager.default.fileExists(atPath: base.path) else {
            throw SourcesMissing(path: base.path)
        }
        let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            if let excluded, url.path.contains(repository.appendingPathComponent(excluded).path) { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    struct SourcesMissing: Error, CustomStringConvertible {
        let path: String
        var description: String { "no sources at \(path)" }
    }

    /// An emoji scalar: emoji presentation, a variation selector 16, or the pictographic planes.
    static func isEmoji(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isEmojiPresentation || scalar.value == 0xFE0F || (0x1F000...0x1FAFF).contains(scalar.value)
    }

    /// `path:line` for each line of `files` that `matches`.
    static func hits(in files: [URL], where matches: (Substring) -> Bool) throws -> [String] {
        var hits: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where matches(line) {
                hits.append("\(file.path.replacingOccurrences(of: repository.path + "/", with: "")):\(number + 1): \(line)")
            }
        }
        return hits
    }

    @Test("no emoji in the app's sources, so none in any UI string")
    func noEmoji() throws {
        let files = try Self.appRoots.flatMap { try Self.swiftFiles(under: $0) }
        #expect(files.count > 50, "the scan found only \(files.count) files")
        let hits = try Self.hits(in: files) { line in line.unicodeScalars.contains(where: Self.isEmoji) }
        #expect(hits.isEmpty, "emoji in shipping sources:\n\(hits.joined(separator: "\n"))")
    }

    @Test("no random values in app code, and no Int.random in any shipping code")
    func noRandomValues() throws {
        let appFiles = try Self.appRoots.flatMap { try Self.swiftFiles(under: $0) }
        let appHits = try Self.hits(in: appFiles) { line in
            line.contains(".random(") || line.contains(".randomElement(") || line.contains(".shuffled(")
                || line.contains("Int.random") || line.contains("arc4random")
        }
        #expect(appHits.isEmpty, "random values in app code:\n\(appHits.joined(separator: "\n"))")

        let coreFiles = try Self.swiftFiles(under: Self.coreRoot, excluding: Self.coreExcluded)
        #expect(!coreFiles.isEmpty)
        let coreHits = try Self.hits(in: coreFiles) { line in line.contains("Int.random") }
        #expect(coreHits.isEmpty, "Int.random in TallyCore:\n\(coreHits.joined(separator: "\n"))")
    }

    @Test("the scanner itself: it sees an emoji and a random call in a planted line")
    func scannerSelfTest() {
        #expect("Text(\"Great job \u{1F525}\")".unicodeScalars.contains(where: Self.isEmoji))
        #expect(!"Text(\"12-day streak\") · ▲ 1.3 — \u{201C}What changed\u{201D}".unicodeScalars.contains(where: Self.isEmoji))
    }
}
