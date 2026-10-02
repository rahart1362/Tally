import Foundation
import Synchronization

/// Each key looked up once (PR #27: "Sample entry to full projection" at 0.18-0.37 s against its
/// 0.15 s budget).
///
/// `String(localized: LocalizedStringResource)` reads the catalog again on every call: 75 µs per call
/// on the CI simulator with main's catalog and 200-320 µs with this branch's larger one, where the same
/// lookup through `Bundle` costs 1-8 µs (PERF-DIAG runs 36973679483 and 36973677502, `docs/pmo/reviews/
/// l10n-03b-report.md` §9). The screens' projection makes several hundred of those calls (every due
/// date, status chip and VoiceOver label), so the code that builds rows off the main actor looks its
/// keys up through `L10n.string` instead, which keeps what `String(localized:)` returned:
/// - a key with no argument: its text;
/// - a key whose arguments are all `String`s: its text with a placeholder (a private-use code point)
///   where each argument goes, which every call fills in, in one pass;
/// - a key with one `Int` (a plural): its text for that number, for numbers in `cachedCounts`.
///
/// Each overload takes the `L10n` function itself, not a resource built from it, so a key is never
/// cached with one call's arguments. `String(localized:)` puts a left-to-right `String` argument
/// (`%@`) into the text unchanged, so filling it in afterwards gives the same text, byte for byte
/// (`L10nLookupTests` compares the two); this holds for a function that puts each argument into its
/// `defaultValue` as it is, which every `L10n` function does. Right-to-left text is the exception:
/// `String(localized:)` sets such an argument apart with Unicode isolates, "Was due \u{2068}שלום\u{2069}"
/// (CI run 36976127452), so an argument or a text with any right-to-left character or bidi control
/// is looked up uncached, exactly as before. Entries are per key, table, bundle and locale identifier:
/// a region change (`Locale.current` changes in place) makes new ones, and the language changes only
/// with a relaunch.
extension L10n {
    /// The plural keys' numbers that are cached; any other number is looked up on every call.
    public static let cachedCounts = 0...999

    /// `String(localized: key())` for a key with no argument: `L10n.string(L10n.ToDo.statusMissing)`.
    public static func string(_ key: () -> LocalizedStringResource) -> String {
        LookupCache.text(of: key())
    }

    /// `String(localized: key(first))`: `L10n.string(L10n.Courses.wasDue, day)`.
    public static func string(_ key: (String) -> LocalizedStringResource, _ first: String) -> String {
        LookupCache.filled(key(LookupCache.placeholders[0]), [first]) ?? String(localized: key(first))
    }

    /// `String(localized: key(first, second))`: `L10n.string(L10n.Courses.dueAtTime, day, time)`.
    public static func string(_ key: (String, String) -> LocalizedStringResource,
                              _ first: String, _ second: String) -> String {
        LookupCache.filled(key(LookupCache.placeholders[0], LookupCache.placeholders[1]), [first, second])
            ?? String(localized: key(first, second))
    }

    /// `String(localized: key(first, second, third))`.
    public static func string(_ key: (String, String, String) -> LocalizedStringResource,
                              _ first: String, _ second: String, _ third: String) -> String {
        let probe = key(LookupCache.placeholders[0], LookupCache.placeholders[1], LookupCache.placeholders[2])
        return LookupCache.filled(probe, [first, second, third]) ?? String(localized: key(first, second, third))
    }

    /// `String(localized: key(count))` for a plural key: `L10n.string(L10n.Calendar.itemCount, count)`.
    public static func string(_ key: (Int) -> LocalizedStringResource, _ count: Int) -> String {
        let resource = key(count)
        guard cachedCounts.contains(count) else { return String(localized: resource) }
        return LookupCache.text(of: resource, count: count)
    }
}

/// The cache behind `L10n.string`: a few hundred entries at most (the catalog's keys, the plural
/// keys' small numbers), never evicted.
enum LookupCache {
    /// Private-use code points (U+E000 to U+E002): no catalog text or translation contains one.
    static let placeholders = ["\u{E000}", "\u{E001}", "\u{E002}"]
    private static let firstPlaceholder = 0xE000
    /// Every right-to-left character (Unicode bidi classes R and AL, and the Arabic digits) lies in
    /// these blocks: Hebrew to Arabic Extended-A, the Hebrew and Arabic presentation forms, and the
    /// right-to-left scripts of the supplementary planes. Wider than the classes, never narrower.
    private static let rightToLeftBlocks: [ClosedRange<UInt32>] = [
        0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF,
    ]

    private struct Key: Hashable, Sendable {
        let bundle: String
        let table: String?
        let key: String
        let locale: String
        /// A plural key's number; `nil` for every other key.
        let count: Int?
    }

    private final class Storage: Sendable {
        let texts = Mutex<[Key: String]>([:])
    }

    private static let storage = Storage()

    /// `String(localized: resource)`, looked up once per key (and per number, for a plural).
    static func text(of resource: LocalizedStringResource, count: Int? = nil) -> String {
        guard let key = key(of: resource, count: count) else { return String(localized: resource) }
        if let cached = storage.texts.withLock({ $0[key] }) { return cached }
        let text = String(localized: resource)
        storage.texts.withLock { $0[key] = text }
        return text
    }

    private static func key(of resource: LocalizedStringResource, count: Int?) -> Key? {
        let bundle: String
        switch resource.bundle {
        case .main: bundle = "main"
        case .atURL(let url): bundle = url.absoluteString
        case .forClass(let type): bundle = String(reflecting: type)
        @unknown default: return nil
        }
        return Key(bundle: bundle, table: resource.table, key: resource.key, locale: resource.locale.identifier,
                   count: count)
    }

    /// `probe`'s text with `arguments` filled in, or `nil` when `String(localized:)` may set an argument
    /// apart with Unicode isolates: when the text or an argument has a right-to-left character or a bidi
    /// control. The caller then looks the key up with its arguments, uncached.
    static func filled(_ probe: LocalizedStringResource, _ arguments: [String]) -> String? {
        guard !arguments.contains(where: mayBeIsolated) else { return nil }
        let template = text(of: probe)
        guard !mayBeIsolated(template) else { return nil }
        return fill(template, arguments)
    }

    /// Whether `text` has a right-to-left character or a bidi control (LRM, RLM, ALM, the embeddings,
    /// overrides and isolates).
    static func mayBeIsolated(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.properties.isBidiControl || rightToLeftBlocks.contains { $0.contains(scalar.value) }
        }
    }

    /// `template` with each placeholder replaced by its argument, in one pass, so an argument that
    /// itself holds a placeholder's code point is never rewritten.
    static func fill(_ template: String, _ arguments: [String]) -> String {
        let scalars = template.unicodeScalars
        var text = ""
        text.reserveCapacity(template.utf8.count + arguments.reduce(0) { $0 + $1.utf8.count })
        var runStart = scalars.startIndex
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let argument = Int(scalars[index].value) - firstPlaceholder
            let next = scalars.index(after: index)
            if argument >= 0, argument < arguments.count {
                text.unicodeScalars.append(contentsOf: scalars[runStart..<index])
                text += arguments[argument]
                runStart = next
            }
            index = next
        }
        text.unicodeScalars.append(contentsOf: scalars[runStart..<scalars.endIndex])
        return text
    }
}
