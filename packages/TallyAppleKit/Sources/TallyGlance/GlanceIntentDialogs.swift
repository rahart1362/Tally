import Foundation
import TallyStore
import TallyStrings

// The words of the intents' answers (plan 08 §3.2's renderer pattern): catalog text from
// `L10n.Widgets`, with times, dates and lists formatted for `locale` (`TallyFormat`). The answers
// themselves are worked out in `GlanceIntentAnswers` and `RefreshAnswer`.

extension GlanceIntentAnswers {
    /// The spoken answer: a catalog sentence, then "Plus 2 more.", "You also have 1 overdue." and
    /// "As of 2:14 PM." where they apply, each joined by the catalog's sentence separator.
    public static func dialog(_ answer: GlanceIntentAnswer, calendar: Calendar,
                              locale: Locale = TallyLocale.effective) -> LocalizedStringResource {
        var resource: LocalizedStringResource
        switch answer {
        case .message(let message):
            resource = GlanceText.messageResource(message)
        case .list(let list):
            var extras: [String] = []
            if list.moreCount > 0 {
                let more = list.moreIsLowerBound ? L10n.Widgets.answerMoreAtLeast(list.moreCount) : L10n.Widgets.answerMore(list.moreCount)
                extras.append(GlanceText.resolve(more, locale))
            }
            if list.overdueCount > 0 {
                extras.append(GlanceText.resolve(L10n.Widgets.answerOverdue(list.overdueCount), locale))
            }
            if list.isStale {
                let summary = GlanceSummary(nextUp: nil, laterCount: 0, overdueCount: 0, grades: .notOptedIn, asOf: list.asOf,
                                            isStale: true, asOfIsBeforeToday: list.asOfIsBeforeToday)
                extras.append(GlanceText.resolve(
                    L10n.Widgets.answerAsOf(GlanceText.asOfTime(summary, calendar: calendar, locale: locale)), locale))
            }
            resource = joined(mainSentence(list, calendar: calendar, locale: locale), extras, locale: locale)
        }
        resource.locale = locale
        return resource
    }

    static func mainSentence(_ list: GlanceAnswerList, calendar: Calendar, locale: Locale) -> LocalizedStringResource {
        guard !list.items.isEmpty else {
            return list.kind == .dueToday ? L10n.Widgets.answerNothingToday() : L10n.Widgets.answerNothingSoon()
        }
        let phrases = list.items.map { phrase($0, hidesNames: list.hidesCourseNames, calendar: calendar, locale: locale) }
        let items = TallyFormat.list(phrases, locale: locale)
        return list.kind == .dueToday ? L10n.Widgets.answerDueToday(items) : L10n.Widgets.answerDueNext(items)
    }

    /// "Lab Report 4 (BIO 101), due today at 6:00 PM", or "An assignment, due …" with names hidden.
    static func phrase(_ item: GlanceSummary.Item, hidesNames: Bool, calendar: Calendar, locale: Locale) -> String {
        let when = GlanceText.spokenWhen(item, calendar: calendar, locale: locale)
        if hidesNames { return GlanceText.resolve(L10n.Widgets.answerItemHidden(when), locale) }
        guard let code = item.courseCode else {
            return GlanceText.resolve(L10n.Widgets.answerItemNoCourse(item.title, when), locale)
        }
        return GlanceText.resolve(L10n.Widgets.answerItem(item.title, code, when), locale)
    }

    /// The main sentence followed by `extras`, as one catalog resource: the main sentence itself
    /// when there are none, otherwise the last join, so the dialog is always catalog text.
    static func joined(_ main: LocalizedStringResource, _ extras: [String], locale: Locale) -> LocalizedStringResource {
        guard let last = extras.last else { return main }
        var text = GlanceText.resolve(main, locale)
        for sentence in extras.dropLast() {
            text = GlanceText.resolve(L10n.Widgets.sentences(text, sentence), locale)
        }
        return L10n.Widgets.sentences(text, last)
    }
}

extension RefreshAnswer {
    /// The spoken answer, in `locale`. A saved-data time reads "2:14 PM" when it is from today and
    /// "Tue 2:14 PM" when it is older.
    public func dialog(now: Date, calendar: Calendar, locale: Locale = TallyLocale.effective) -> LocalizedStringResource {
        var resource: LocalizedStringResource
        switch self {
        case .updated:
            resource = L10n.Widgets.refreshUpdated()
        case .stillRefreshing:
            resource = L10n.Widgets.refreshStillRunning()
        case .offline(let showing?):
            resource = L10n.Widgets.refreshOffline(Self.when(showing, now: now, calendar: calendar, locale: locale))
        case .offline(nil):
            resource = L10n.Widgets.refreshOfflineNoData()
        case .signInExpired:
            resource = L10n.Widgets.refreshSignInExpired()
        case .failed(let showing?):
            resource = L10n.Widgets.refreshFailed(Self.when(showing, now: now, calendar: calendar, locale: locale))
        case .failed(nil):
            resource = L10n.Widgets.refreshFailedNoData()
        case .openTally:
            resource = L10n.Widgets.refreshOpenTally()
        }
        resource.locale = locale
        return resource
    }

    /// "Open Tally to refresh.", for a process that cannot refresh (the widget extension's half of
    /// "Refresh Tally"). Parameterless on purpose: a caller in the extension then references
    /// TallyGlance's symbols only. In a test build Xcode turns the shared package products into
    /// frameworks, and the extension links TallyGlance alone, so a call that named `FreshnessState`
    /// (TallyDomain) or evaluated `TallyLocale.effective` (TallyStrings) as a default argument in the
    /// extension's own code failed to link (run 36943166823).
    public static func openTallyDialog() -> LocalizedStringResource {
        RefreshAnswer.openTally.dialog(now: Date(), calendar: .autoupdatingCurrent)
    }

    static func when(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let summary = GlanceSummary(nextUp: nil, laterCount: 0, overdueCount: 0, grades: .notOptedIn, asOf: date, isStale: true,
                                    asOfIsBeforeToday: date < calendar.startOfDay(for: now))
        return GlanceText.asOfTime(summary, calendar: calendar, locale: locale)
    }
}
