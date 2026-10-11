import Foundation
import Testing
import UIKit
import TallyStrings
@testable import TallyFeatures

/// Plan 08 L10N-04 (owner decision 2026-10-11, "machine pass now, review later"): every Spanish
/// value this work package writes carries the catalog state `needs_review`, never `translated`.
/// **This is the verification the brief asks for first**: does Xcode actually compile a
/// `needs_review` value into the build, and does it resolve at run time — or does String Catalogs'
/// tooling silently fall back to English for anything short of `translated`? If it falls back,
/// `scripts/ci/check_string_catalogs.py --release` would be the only thing standing between a
/// half-English "Spanish" release and the App Store, so the fallback path
/// (`docs/l10n/es-review-status.md`, §ownership in the L10N-04 report) matters only if this test
/// is red.
///
/// Coverage: every placeholder-free, non-plural key in the shared catalog (527 of 706 —
/// `L10N04SpanishFixture.samples`, generated from the same source `main.json`/`main_es_merged.json`
/// extraction this work package used to write the translations, so this test and the catalog
/// cannot silently drift apart) resolves generically, by key, through `Bundle.localizedString
/// (forKey:value:table:)` on the compiled `es.lproj` sub-bundle directly — not `LocalizedStringResource`,
/// whose keyed initializer takes its key as `StaticString` (a compile-time literal), which a
/// runtime loop over a key list cannot supply. Forcing a language via its own `.lproj` sub-bundle
/// is the standard way to read a specific language's compiled strings regardless of the device's
/// or the test's own locale. Plural and placeholder keys need their own interpolation to resolve
/// correctly (the plural/argument wiring lives in the `L10n` wrapper, not in a bare key lookup), so
/// those are spot-checked through their real wrappers below instead of the generic loop.
@Suite("L10N-04: needs_review Spanish values compile and resolve at run time")
struct L10N04SpanishResolutionTests {
    private static let es = Locale(identifier: "es")

    /// The shared `TallyStrings` resource bundle actually embedded in the running app (the same
    /// helper `LocalizationTests.stringsBundle` uses) — not `#bundle` from this test target, which
    /// would resolve to TallyAppTests' own (catalog-less) bundle.
    private static func stringsBundle() throws -> Bundle {
        let app = Bundle.main
        let items = try FileManager.default.contentsOfDirectory(at: app.bundleURL, includingPropertiesForKeys: nil)
        let url = try #require(items.first { $0.lastPathComponent.hasSuffix("TallyStrings.bundle") },
                                "no TallyStrings.bundle next to \(app.bundleURL.lastPathComponent)")
        return try #require(Bundle(url: url))
    }

    /// The compiled `es.lproj` directly inside the `TallyStrings` resource bundle: a sub-bundle
    /// whose own `preferredLocalizations` is just `["es"]`, so `localizedString(forKey:value:table:)`
    /// on it returns the Spanish string regardless of the device's or the test process's own
    /// locale — the standard "force a language" technique, not `LocalizedStringResource` (whose
    /// keyed initializer needs a compile-time `StaticString` key, which a runtime key list can't
    /// supply).
    private static func esSubBundle() throws -> Bundle {
        let strings = try Self.stringsBundle()
        let lprojPath = try #require(strings.path(forResource: "es", ofType: "lproj"),
                                      "no es.lproj inside \(strings.bundleURL.lastPathComponent)")
        return try #require(Bundle(path: lprojPath), "es.lproj at \(lprojPath) is not a bundle")
    }

    /// Every placeholder-free key resolves to its Spanish value — not the English `defaultValue`,
    /// and not the raw key (`Bundle.localizedString` falls back to the key itself when a table has
    /// no match, so a lookup failure shows up as a mismatch here, never a silent pass). 527 keys,
    /// all `needs_review`.
    @Test("Every placeholder-free TallyStrings key resolves to Spanish under the es locale")
    func everyPlaceholderFreeKeyResolvesInSpanish() throws {
        let esBundle = try Self.esSubBundle()
        var wrong: [String] = []
        for sample in L10N04SpanishFixture.samples {
            let resolved = esBundle.localizedString(forKey: sample.key, value: nil, table: "Localizable")
            if resolved != sample.spanish {
                wrong.append("\(sample.key): got \(resolved.debugDescription), want \(sample.spanish.debugDescription)")
            }
        }
        let detail = wrong.prefix(15).joined(separator: "\n")
        #expect(wrong.isEmpty, "\(wrong.count) of \(L10N04SpanishFixture.samples.count) keys did not resolve to Spanish:\n\(detail)")
    }

    /// A specific `needs_review` key, resolved the same way `LocalizationTests.heroCaptionPlural`
    /// resolves English: this is the brief's own example ("the hosted … test, run in es, must show
    /// Spanish for a needs_review key"). "Promedio de 1 curso"/"… cursos" can only come from the
    /// catalog's own plural forms, never from the English `defaultValue`.
    @MainActor
    @Test("The hero caption's plural forms come from the catalog in Spanish too",
          arguments: [(0, "Promedio de 0 cursos"), (1, "Promedio de 1 curso"), (5, "Promedio de 5 cursos")])
    func heroCaptionPluralSpanish(count: Int, expected: String) {
        var resource = L10n.Dashboard.averageOfCourses(count)
        resource.locale = Self.es
        #expect(String(localized: resource) == expected)
    }

    /// Placeholder keys resolve correctly in Spanish through their real wrappers, positional
    /// reordering included (`%1$@`/`%2$@` keep the same two arguments, Spanish just says them in a
    /// different order in `goalMinimumOrMore`-style phrasing is not used here, but `scoreOutOf` and
    /// the sparkline both carry two arguments through unchanged order, which is the common case).
    @Test("Placeholder keys resolve correctly in Spanish")
    func placeholderKeysResolveInSpanish() {
        var scoreOutOf = L10n.CourseDetail.scoreOutOf("92", "100")
        scoreOutOf.locale = Self.es
        #expect(String(localized: scoreOutOf) == "92 de 100")

        var dueDay = L10n.Courses.dueDay("Fri")
        dueDay.locale = Self.es
        #expect(String(localized: dueDay) == "Vence Fri")
    }

    /// The two post-freeze keys (plan 08 §6: UX-SPARK's trend sentences, PR #38; the Course Options
    /// row label, PR #42 D17) were translated along with the rest — they are not a separate pass.
    @Test("The two post-freeze keys resolve in Spanish")
    func postFreezeKeysResolveInSpanish() {
        var up = L10n.Courses.sparklineTrendUp("78.0", "91.4")
        up.locale = Self.es
        #expect(String(localized: up) == "Tendencia: subió de 78.0 a 91.4 por ciento")

        var down = L10n.Courses.sparklineTrendDown("91.4", "78.0")
        down.locale = Self.es
        #expect(String(localized: down) == "Tendencia: bajó de 91.4 a 78.0 por ciento")

        var steady = L10n.Courses.sparklineTrendSteady("90.1")
        steady.locale = Self.es
        #expect(String(localized: steady) == "Tendencia: estable en 90.1 por ciento")

        var menuRow = L10n.GradeOverride.menuRowTitle()
        menuRow.locale = Self.es
        #expect(String(localized: menuRow) == "Calificaciones fuera de Canvas")
    }

    /// L-2 / L10N-04 brief item 3: the Settings → Language row's own gating condition ("the row
    /// appears only when more than one localization ships") and its link
    /// (`UIApplication.openSettingsURLString`). The row itself is SwiftUI and not inspectable
    /// without a UI test (the Audit tour's es dispatch is the UI-level check, per the brief); this
    /// is the hosted half, run on every PR rather than only on an Audit tour dispatch.
    @Test("The Settings Language row's condition holds for the shipped app, and its link resolves")
    func languageRowConditionAndLink() throws {
        let shipped = Bundle.main.localizations.filter { $0 != "Base" }
        #expect(Set(shipped) == ["en", "es"], "\(shipped)")
        #expect(shipped.count > 1, "the row's own condition (SettingsView.languageSection): more than one localization ships")
        // Not pinned to a specific scheme string: Apple's own constant, not a literal this
        // work package controls, and it has changed shape across iOS versions. The contract
        // `SettingsView.languageSection` relies on is just that it parses to a URL `openURL` can
        // open.
        let url = try #require(URL(string: UIApplication.openSettingsURLString))
        #expect(url.scheme?.isEmpty == false, "\(url)")
    }

    /// The row's value text is the system's own language name, never a catalog string
    /// (L10N-04 brief item 3) — `Locale.current.localizedString(forIdentifier:)` must actually
    /// know the two shipped language codes, in whichever language is currently running.
    @Test("The system names both shipped languages for the Language row's value text")
    func systemNamesShippedLanguages() {
        #expect(Locale.current.localizedString(forIdentifier: "en") != nil)
        #expect(Locale.current.localizedString(forIdentifier: "es") != nil)
    }
}
