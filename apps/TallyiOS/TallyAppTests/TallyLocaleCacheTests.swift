import Foundation
import Testing
import TallyStrings

/// `TallyLocale.effective` is cached (PR #27: rebuilding it for every formatted value blew the
/// sample-entry budget). The cache must still give the same locale as building it afresh, before
/// and after iOS reports a locale change.
@Suite("TallyLocale.effective cache")
struct TallyLocaleCacheTests {
    private func uncached() -> Locale {
        TallyLocale.effective(uiLanguage: Bundle.main.preferredLocalizations.first, current: .current)
    }

    @Test("the cached locale equals a fresh one, before and after a locale change")
    func cachedMatchesFresh() {
        #expect(TallyLocale.effective == TallyLocale.effective)
        #expect(TallyLocale.effective == uncached())
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        #expect(TallyLocale.effective == uncached())
    }
}
