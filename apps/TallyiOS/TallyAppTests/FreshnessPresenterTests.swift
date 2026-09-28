import Foundation
import Testing
import TallyDomain
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
}
