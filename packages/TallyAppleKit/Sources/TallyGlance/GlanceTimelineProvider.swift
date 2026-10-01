import AppIntents
import Foundation
import TallyStore
import WidgetKit

public struct GlanceEntry: TimelineEntry, Equatable, Sendable {
    public let date: Date
    public let content: GlanceContent

    public init(date: Date, content: GlanceContent) {
        self.date = date
        self.content = content
    }

    public init(_ moment: GlanceMoment) {
        self.init(date: moment.date, content: moment.content)
    }

    /// Smart Stack relevance (insights-at-a-glance.md §1.5): high while the next item is due
    /// within 3 hours, for as long as it is, low otherwise (`GlanceTimelinePlanner.relevance`).
    public var relevance: TimelineEntryRelevance? {
        let relevance = GlanceTimelinePlanner.relevance(of: content, at: date)
        return TimelineEntryRelevance(score: relevance.score, duration: relevance.duration)
    }
}

/// Whose glance a widget reads (FAM-11). Today there is one: the signed-in student's own. M3-E2
/// adds the parent's per-student glances here, and maps its `StudentEntity` parameter to them in
/// the widgets' configuration intent; the widget kinds and every view stay as they are.
public enum GlanceScope: Equatable, Sendable {
    case signedInStudent
}

/// A widget configuration intent that says whose glance to read (FAM-11). The widget extension's
/// one configuration intent conforms; today it has no parameters and answers `.signedInStudent`.
public protocol GlanceScoped {
    var glanceScope: GlanceScope { get }
}

/// The widgets' one timeline provider (plan 06 step 11), for every widget kind. Each call reads
/// the configured scope's glance once (`GlanceReader`), plans the timeline over it
/// (`GlanceTimelinePlanner`) and hands WidgetKit the entries with `.after(first boundary)`. The
/// placeholder and the gallery preview read nothing.
///
/// An `AppIntentTimelineProvider` from the start, though the configuration has no parameters yet:
/// adding M3-E2's optional student parameter to the same intent keeps every placed widget (its
/// stored configuration decodes with the new parameter unset) and every kind.
public struct GlanceIntentTimelineProvider<Intent: WidgetConfigurationIntent & GlanceScoped>: AppIntentTimelineProvider {
    private let read: @Sendable (GlanceScope) async -> GlanceReadResult

    /// `read` is injectable for tests; the widget uses `readFromAppGroup`.
    public init(read: @escaping @Sendable (GlanceScope) async -> GlanceReadResult = { scope in
        await GlanceWidgetSource.readFromAppGroup(scope)
    }) {
        self.read = read
    }

    public func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), content: .placeholder)
    }

    public func snapshot(for configuration: Intent, in context: Context) async -> GlanceEntry {
        if context.isPreview { return placeholder(in: context) }
        return GlanceEntry(await plan(configuration.glanceScope).current)
    }

    public func timeline(for configuration: Intent, in context: Context) async -> Timeline<GlanceEntry> {
        let plan = await plan(configuration.glanceScope)
        return Timeline(entries: plan.moments.map(GlanceEntry.init), policy: .after(plan.reloadAfter))
    }

    private func plan(_ scope: GlanceScope) async -> GlanceTimelinePlanner.Plan {
        let result = await read(scope)
        return GlanceTimelinePlanner.plan(for: result, now: Date(), calendar: .current)
    }
}

/// Where a widget's glance comes from.
public enum GlanceWidgetSource {
    /// The glance from the App Group, with the configuration in the widget's own Info.plist.
    public static func readFromAppGroup(_ scope: GlanceScope) async -> GlanceReadResult {
        switch scope {
        case .signedInStudent:
            guard let configuration = GlanceConfiguration.from(infoDictionary: Bundle.main.infoDictionary) else {
                return .unavailable
            }
            let reader = GlanceReader(
                storeRoot: GlanceStoreLocation.appGroupStoreRoot(appGroupID: configuration.appGroupID),
                keyStore: WidgetVaultKeyReader(appBundleID: configuration.appBundleID,
                                               accessGroup: configuration.keychainAccessGroup))
            return await reader.read()
        }
    }
}
