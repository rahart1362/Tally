import Foundation

/// The one locale Tally formats numbers, dates and times with (plan 08 §3.3).
///
/// iOS picks Tally's UI language from the languages Tally ships (the main bundle's
/// localizations), but `Locale.current` follows the iPhone's own language and region. On a
/// German-language iPhone, with no German in Tally, the words are English while `Locale.current`
/// is still `de_DE`, so a formatter left on `Locale.current` can put German day names inside
/// English sentences ("Due morgen at 14:00"). `effective` keeps the user's region and preferences
/// (decimal comma, 24-hour time, first weekday, any overrides set in iOS Settings) and swaps in the
/// language the UI is actually shown in: `en_DE` in that case.
public enum TallyLocale {
    /// The UI language actually in use (`Bundle.main.preferredLocalizations.first`) with the
    /// user's region and preferences (`Locale.current`). In the widget, `Bundle.main` is the
    /// extension, which ships the same localizations as the app.
    public static var effective: Locale {
        effective(uiLanguage: Bundle.main.preferredLocalizations.first, current: .current)
    }

    /// `current` with its language replaced by `uiLanguage` (a localization name such as "en",
    /// "es" or "zh-Hant"). `current` itself when the languages already match, when `uiLanguage`
    /// is missing or "Base", or when it names no language.
    public static func effective(uiLanguage: String?, current: Locale) -> Locale {
        guard let uiLanguage, uiLanguage != baseLocalization else { return current }
        // Components, not `Locale.Language`: the latter fills in the likely script ("en" becomes
        // "en-Latn"), which would put a script into every effective identifier.
        let shown = Locale.Language.Components(identifier: uiLanguage)
        guard let code = shown.languageCode else { return current }
        let sameLanguage = current.language.languageCode == code
            && (shown.script == nil || current.language.script == shown.script)
        if sameLanguage { return current }
        var components = Locale.Components(locale: current)
        components.languageComponents = Locale.Language.Components(
            languageCode: code, script: shown.script, region: current.region
        )
        return Locale(components: components)
    }

    /// Xcode's "Base" localization names no language.
    static let baseLocalization = "Base"
}
