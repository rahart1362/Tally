import Foundation
import Testing
import TallyDomain
import TallyStrings
@testable import TallyFeatures

/// UX-WP-06: "Unit-test every state" (ux-ui.md §3.3's freshness table). Uses a fixed `now` and
/// `en_US` locale throughout so the assertions are deterministic regardless of the machine's
/// locale/timezone.
@Suite("FreshnessPresenter: every FreshnessState maps to the kit-11 copy")
struct FreshnessPresenterTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000) // fixed instant
    private let locale = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!

    @Test("noCache: a total presenter, not in the UX table, still returns something honest")
    func noCache() {
        let p = FreshnessPresenter.present(.noCache, now: now, locale: locale, timeZone: utc)
        #expect(p.shortText == "Not refreshed yet")
        #expect(p.longText == nil)
        #expect(p.action == .refresh)
    }

    @Test("fresh within 60s: 'Updated just now', no breadcrumb, checkmark, Refresh action")
    func freshJustNow() {
        let p = FreshnessPresenter.present(.fresh(at: now.addingTimeInterval(-30)), now: now, locale: locale, timeZone: utc)
        #expect(p.shortText == "Updated just now")
        #expect(p.longText == nil)
        #expect(p.symbol == .checkmarkCircle)
        #expect(p.action == .refresh)
        #expect(!p.showsBreadcrumb)
    }

    @Test("fresh, aging (earlier today): 'Updated <time>', clock symbol, still Refresh")
    func freshAgingSameDay() {
        let earlier = now.addingTimeInterval(-3600) // 1h ago, same UTC day
        let p = FreshnessPresenter.present(.fresh(at: earlier), now: now, locale: locale, timeZone: utc)
        #expect(p.shortText.hasPrefix("Updated "))
        #expect(p.shortText != "Updated just now")
        #expect(p.symbol == .clock)
        #expect(p.action == .refresh)
        #expect(!p.showsBreadcrumb)
    }

    @Test("fresh, several days ago: shows a month/day, not a weekday+time")
    func freshOld() {
        let old = now.addingTimeInterval(-14 * 24 * 3600)
        let p = FreshnessPresenter.present(.fresh(at: old), now: now, locale: locale, timeZone: utc)
        // Should read like "Updated Sep 12" — no colon (no time-of-day component).
        #expect(p.shortText.hasPrefix("Updated "))
        #expect(!p.shortText.contains(":"))
    }

    @Test("refreshing: spinner, disabled action, no breadcrumb")
    func refreshing() {
        let p = FreshnessPresenter.present(.refreshing(showing: now.addingTimeInterval(-120)), now: now, locale: locale, timeZone: utc)
        #expect(p.shortText.contains("Refreshing…"))
        #expect(p.symbol == .spinner)
        #expect(p.action == .none)
        #expect(!p.showsBreadcrumb)
    }

    @Test("delayed with saved data: breadcrumb shown, Retry action")
    func delayedWithData() {
        let showing = now.addingTimeInterval(-600)
        let p = FreshnessPresenter.present(.delayed(showing: showing), now: now, locale: locale, timeZone: utc)
        #expect(p.shortText.hasPrefix("Saved "))
        #expect(p.showsBreadcrumb)
        #expect(p.longText?.contains("Live refresh is taking longer") == true)
        #expect(p.action == .retry)
    }

    @Test("delayed with no cache yet (first sync slow): no stale breadcrumb")
    func delayedNoData() {
        let p = FreshnessPresenter.present(.delayed(showing: nil), now: now, locale: locale, timeZone: utc)
        #expect(!p.showsBreadcrumb)
        #expect(p.longText == nil)
    }

    @Test("offline with saved data: breadcrumb, no action (auto-retry)")
    func offlineWithData() {
        let showing = now.addingTimeInterval(-600)
        let p = FreshnessPresenter.present(.offline(showing: showing), now: now, locale: locale, timeZone: utc)
        #expect(p.showsBreadcrumb)
        #expect(p.longText == "You're offline — showing your latest saved data.")
        #expect(p.action == .none)
    }

    @Test("authExpired with saved data: breadcrumb, Sign In action")
    func authExpiredWithData() {
        let showing = now.addingTimeInterval(-600)
        let p = FreshnessPresenter.present(.authExpired(showing: showing), now: now, locale: locale, timeZone: utc)
        #expect(p.showsBreadcrumb)
        #expect(p.longText?.contains("sign-in expired") == true)
        #expect(p.action == .signIn)
    }

    @Test("failed (non-auth) with saved data: breadcrumb, Retry action", arguments: RefreshFailure.allCases)
    func failedWithData(_ failure: RefreshFailure) {
        let showing = now.addingTimeInterval(-600)
        let p = FreshnessPresenter.present(.failed(failure, showing: showing), now: now, locale: locale, timeZone: utc)
        #expect(p.showsBreadcrumb)
        #expect(p.longText?.contains("Couldn't refresh") == true)
        #expect(p.action == .retry)
    }

    @Test("failed with no saved data: no breadcrumb")
    func failedNoData() {
        let p = FreshnessPresenter.present(.failed(.server, showing: nil), now: now, locale: locale, timeZone: utc)
        #expect(!p.showsBreadcrumb)
    }

    // MARK: - Plan 08 §3.3 fix: the formatting locale (L10N-03a)

    /// The named fix: `present(…)` used to default to a hard-coded `en_US`, so an en-GB user
    /// always saw 12-hour times here. This drives the formatter with `en_GB` directly (as
    /// `TallyLocale.effective` would resolve it on an en-GB device) and checks for 24-hour time:
    /// no "AM"/"PM", and a colon in the clock time.
    @Test("fresh, aging, en_GB: 24-hour time, not 12-hour")
    func freshAgingEnGBUses24HourTime() {
        let earlier = now.addingTimeInterval(-3600) // 1h ago, same UTC day
        let enGB = Locale(identifier: "en_GB")
        let p = FreshnessPresenter.present(.fresh(at: earlier), now: now, locale: enGB, timeZone: utc)
        #expect(p.shortText.hasPrefix("Updated "))
        #expect(p.shortText.contains(":"))
        #expect(!p.shortText.contains("AM"))
        #expect(!p.shortText.contains("PM"))
    }

    /// The breadcrumb's "showing saved data from …" time is the same `when(...)` formatter, so it
    /// is 24-hour for en_GB too.
    @Test("delayed breadcrumb, en_GB: the saved-data time is 24-hour")
    func delayedBreadcrumbEnGBUses24HourTime() {
        let showing = now.addingTimeInterval(-3600)
        let enGB = Locale(identifier: "en_GB")
        let p = FreshnessPresenter.present(.delayed(showing: showing), now: now, locale: enGB, timeZone: utc)
        #expect(p.longText?.contains("AM") == false)
        #expect(p.longText?.contains("PM") == false)
    }

    /// `FreshnessPresenter.swift:31`'s default used to be the literal `Locale(identifier: "en_US")`
    /// (plan 08 §3.3). It is now `TallyLocale.effective`: calling with no `locale:` argument must
    /// behave identically to calling with `locale: TallyLocale.effective` explicitly, for every
    /// case that produces locale-formatted text.
    ///
    /// UNVERIFIED by mutation in this CI environment specifically: `TallyLocale.effective` reduces
    /// to `Locale.current` while Tally ships English only (`TallyLocale.swift`'s `sameLanguage`
    /// branch), and CI's simulator locale is itself en_US (matching the L10N-01 hand-off's own
    /// documented limit on its UI-test pin, `l10n-infra-report.md` §8 item 3), so a revert of this
    /// default back to the `en_US` literal would not change this test's result in that environment.
    /// It still pins the intended behaviour, and would catch the mutation on any other locale.
    @Test("the default locale is TallyLocale.effective, not a hard-coded en_US", arguments: [
        FreshnessState.fresh(at: Date(timeIntervalSince1970: 1_790_000_000 - 3600)),
        .delayed(showing: Date(timeIntervalSince1970: 1_790_000_000 - 600)),
        .offline(showing: Date(timeIntervalSince1970: 1_790_000_000 - 600)),
        .authExpired(showing: Date(timeIntervalSince1970: 1_790_000_000 - 600)),
        .failed(.server, showing: Date(timeIntervalSince1970: 1_790_000_000 - 600)),
    ])
    func defaultLocaleMatchesTallyLocaleEffective(_ state: FreshnessState) {
        let withDefault = FreshnessPresenter.present(state, now: now, timeZone: utc)
        let withEffective = FreshnessPresenter.present(state, now: now, locale: TallyLocale.effective, timeZone: utc)
        #expect(withDefault.shortText == withEffective.shortText)
        #expect(withDefault.longText == withEffective.longText)
    }
}
