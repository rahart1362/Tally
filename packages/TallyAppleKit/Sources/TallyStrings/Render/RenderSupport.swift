import Foundation

/// `resource` resolved to a `String` in `locale`: the catalog's text for the locale's language
/// (English when Tally does not ship that language), with its arguments formatted for the locale.
/// The renderers (plan 08 L10N-02) take the locale explicitly, defaulting to
/// `TallyLocale.effective`, so tests pin it and the words and the formatted values agree.
func resolve(_ resource: LocalizedStringResource, _ locale: Locale) -> String {
    var resource = resource
    resource.locale = locale
    return String(localized: resource)
}
