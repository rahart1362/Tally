import AppIntents
import Foundation
import TallyGlance
import TallyIntents
import TallyStrings

/// Tally's Focus filter (integrations.md §2.6; WWDC22 "Meet Focus filters"): a "Study" or "Exam"
/// Focus lets through only the chosen courses' alerts, or only urgent ones. iOS applies it with the
/// predicate in `appContext` (`FocusFilterCriteria`), which never silences a notification that
/// carries no criteria. Tally's notifications carry none yet: the scheduler that would set them is
/// not this work package's file, so until it does, this filter is configured and kept by the
/// system but changes nothing (see the M3-D report). The spec's "Hide course names" parameter waits
/// for the same change, and the Dashboard chip for the Dashboard's owner.
struct TallyFocusFilter: SetFocusFilterIntent {
    static let title = LocalizedStringResource("intent.focus.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.focus.description", table: "AppIntents"))

    @Parameter(title: LocalizedStringResource("intent.focus.courses", table: "AppIntents"))
    var courses: [CourseEntity]?

    @Parameter(title: LocalizedStringResource("intent.focus.onlyUrgent", table: "AppIntents"), default: false)
    var onlyUrgent: Bool

    init() {}

    var displayRepresentation: DisplayRepresentation {
        let codes = (courses ?? []).map(\.code)
        let locale = TallyLocale.effective
        let coursesText = codes.isEmpty ? resolved(L10n.Widgets.focusAllCourses(), locale) : TallyFormat.list(codes, locale: locale)
        let alertsText = resolved(onlyUrgent ? L10n.Widgets.focusOnlyUrgent() : L10n.Widgets.focusAllAlerts(), locale)
        return DisplayRepresentation(title: "\(coursesText)", subtitle: "\(alertsText)", image: nil)
    }

    var appContext: FocusFilterAppContext {
        FocusFilterAppContext(notificationFilterPredicate: FocusFilterCriteria.predicate(
            courseIDs: (courses ?? []).map(\.id), onlyUrgent: onlyUrgent))
    }

    func perform() async throws -> some IntentResult {
        .result()
    }

    private func resolved(_ resource: LocalizedStringResource, _ locale: Locale) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }
}

/// A course, as the Focus filter offers it: its opaque Canvas ID and short code, read from the
/// glance (no course names, no grades).
struct CourseEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intent.course.type", table: "AppIntents"), numericFormat: nil)
    static let defaultQuery = CourseEntityQuery()

    let id: String
    let code: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(code)", subtitle: nil, image: nil)
    }
}

struct CourseEntityQuery: EntityQuery {
    init() {}

    func entities(for identifiers: [CourseEntity.ID]) async throws -> [CourseEntity] {
        let wanted = Set(identifiers)
        return await Self.courses().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CourseEntity] {
        await Self.courses()
    }

    static func courses() async -> [CourseEntity] {
        let result = await GlanceReader.appProcess().read()
        return GlanceIntentAnswers.courses(result, now: Date()).map { CourseEntity(id: $0.id, code: $0.code) }
    }
}
