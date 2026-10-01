import Foundation
import TallyDomain
import TallyStrings

/// UX-WP-06: a pure presenter mapping `FreshnessState` (TallyDomain) to kit-11 copy
/// (ux-ui.md §3.3's table). Every case is a plain function of its inputs — no I/O, no clock
/// reads — so every state is unit-testable with a fixed `now`.
/// `nonisolated`: `TallyFeatures` defaults to `MainActor` isolation (Package.swift), but this
/// presenter is a pure function with no UI/main-thread dependency — marking it explicitly lets it
/// (and its tests) be called synchronously from any context.
public nonisolated enum FreshnessPresenter {
    public nonisolated enum Symbol: Sendable, Equatable {
        case checkmarkCircle, clock, spinner, clockBadgeExclamation, wifiSlash, exclamationTriangle, personBadgeExclamation
    }

    public nonisolated enum Action: Sendable, Equatable {
        case refresh, retry, signIn, none
    }

    /// `longText` is the global breadcrumb copy; `nil` whenever `state.showsStaleBreadcrumb`
    /// is `false` (ux-ui.md §3.3: "shown only in delayed, offline, failed and authExpired", and
    /// only once there is saved data to describe — `FreshnessState.showing != nil`).
    public nonisolated struct Presentation: Sendable, Equatable {
        public let shortText: String
        public let longText: String?
        public let symbol: Symbol
        public let action: Action
        public var showsBreadcrumb: Bool { longText != nil }
    }

    /// Plan 08 §3.3 (L10N-03a fix): the default used to be hard-coded `en_US`, so an en-GB user
    /// always saw 12-hour times here, before any translation existed. No caller passed `locale:`
    /// (`FreshnessViews.swift:25, 53, 74`; `SettingsView.swift:182`), so this now defaults to the
    /// one formatting locale the rest of the app uses (plan 08 §3.3).
    public static func present(
        _ state: FreshnessState, now: Date, locale: Locale = Locale(identifier: "en_US"), timeZone: TimeZone = .current
    ) -> Presentation {
        switch state {
        case .noCache:
            // Not in ux-ui.md §3.3's table (that table starts at "fresh"): before any successful
            // sync the app shows the first-sync skeleton, not this footer. Included here only so
            // the presenter is total; UNVERIFIED against the UX doc.
            return Presentation(shortText: String(localized: L10n.Freshness.notRefreshedYet()), longText: nil,
                                symbol: .clock, action: .refresh)

        case .fresh(let at):
            let justNow = now.timeIntervalSince(at) < 60
            let shortText = justNow
                ? String(localized: L10n.Freshness.updatedJustNow())
                : String(localized: L10n.Freshness.updated(when(at, now: now, locale: locale, timeZone: timeZone)))
            return Presentation(shortText: shortText, longText: nil, symbol: justNow ? .checkmarkCircle : .clock, action: .refresh)

        case .refreshing(let showing):
            let base = showing.map { String(localized: L10n.Freshness.updated(when($0, now: now, locale: locale, timeZone: timeZone))) }
                ?? String(localized: L10n.Freshness.refreshingFallback())
            return Presentation(shortText: String(localized: L10n.Freshness.refreshingSuffix(base)), longText: nil,
                                symbol: .spinner, action: .none)

        case .delayed(let showing):
            guard let showing else {
                // "showing == nil means the first sync is slow: there is no cache yet, so no
                // stale breadcrumb" (FreshnessState doc comment).
                return Presentation(shortText: String(localized: L10n.Freshness.firstSyncSlow()), longText: nil,
                                    symbol: .clockBadgeExclamation, action: .retry)
            }
            let saved = when(showing, now: now, locale: locale, timeZone: timeZone)
            return Presentation(shortText: String(localized: L10n.Freshness.saved(saved)),
                                longText: String(localized: L10n.Freshness.delayedLong(saved)),
                                symbol: .clockBadgeExclamation, action: .retry)

        case .offline(let showing):
            guard let showing else {
                return Presentation(shortText: String(localized: L10n.Freshness.offlineNoData()), longText: nil,
                                    symbol: .wifiSlash, action: .none)
            }
            let saved = when(showing, now: now, locale: locale, timeZone: timeZone)
            return Presentation(shortText: String(localized: L10n.Freshness.saved(saved)),
                                longText: String(localized: L10n.Freshness.offlineLong()),
                                symbol: .wifiSlash, action: .none)

        case .authExpired(let showing):
            guard let showing else {
                return Presentation(shortText: String(localized: L10n.Freshness.signInExpired()), longText: nil,
                                    symbol: .personBadgeExclamation, action: .signIn)
            }
            let saved = when(showing, now: now, locale: locale, timeZone: timeZone)
            return Presentation(shortText: String(localized: L10n.Freshness.saved(saved)),
                                longText: String(localized: L10n.Freshness.authExpiredLong(saved)),
                                symbol: .personBadgeExclamation, action: .signIn)

        case .failed(_, let showing):
            guard let showing else {
                return Presentation(shortText: String(localized: L10n.Freshness.couldntRefreshYet()), longText: nil,
                                    symbol: .exclamationTriangle, action: .retry)
            }
            let saved = when(showing, now: now, locale: locale, timeZone: timeZone)
            return Presentation(shortText: String(localized: L10n.Freshness.saved(saved)),
                                longText: String(localized: L10n.Freshness.failedLong(saved)),
                                symbol: .exclamationTriangle, action: .retry)
        }
    }

    /// "2:14 PM" today; "Tue 2:14 PM" within the last 6 days; "Sep 12" otherwise
    /// (ux-ui.md §3.3's three examples).
    private static func when(_ date: Date, now: Date, locale: Locale, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "en_US"), calendar: calendar, timeZone: timeZone))
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days >= 0, days < 7 {
            // `.time(_:)` is not a chainable instance modifier on `Date.FormatStyle` (only a
            // static factory unrelated to this use); build the time-of-day from the same
            // per-component modifiers `.weekday`/`.month`/`.day` already use.
            return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
                .weekday(.abbreviated).hour().minute())
        }
        return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
            .month(.abbreviated).day())
    }
}
