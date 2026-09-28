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
}

/// The widgets' one timeline provider (plan 06 step 11). Each call reads the glance once
/// (`GlanceReader`), plans the timeline over it (`GlanceTimelinePlanner`) and hands WidgetKit the
/// entries with `.after(first boundary)`. The placeholder and the gallery preview read nothing.
public struct GlanceTimelineProvider: TimelineProvider {
    private let read: @Sendable () async -> GlanceReadResult

    /// `read` is injectable for tests; the widget uses `readFromAppGroup()`.
    public init(read: @escaping @Sendable () async -> GlanceReadResult = GlanceTimelineProvider.readFromAppGroup) {
        self.read = read
    }

    public func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), content: .placeholder)
    }

    public func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let deliver = OneShot(completion)
        Task { [read] in
            deliver(GlanceEntry(await Self.plan(read).current))
        }
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let deliver = OneShot(completion)
        Task { [read] in
            let plan = await Self.plan(read)
            deliver(Timeline(entries: plan.moments.map(GlanceEntry.init), policy: .after(plan.reloadAfter)))
        }
    }

    /// The glance from the App Group, with the configuration in the widget's own Info.plist.
    public static func readFromAppGroup() async -> GlanceReadResult {
        guard let configuration = GlanceConfiguration.from(infoDictionary: Bundle.main.infoDictionary) else {
            return .unavailable
        }
        let reader = GlanceReader(
            storeRoot: GlanceStoreLocation.appGroupStoreRoot(appGroupID: configuration.appGroupID),
            keyStore: WidgetVaultKeyReader(appBundleID: configuration.appBundleID,
                                           accessGroup: configuration.keychainAccessGroup))
        return await reader.read()
    }

    static func plan(_ read: @Sendable () async -> GlanceReadResult) async -> GlanceTimelinePlanner.Plan {
        let result = await read()
        return GlanceTimelinePlanner.plan(for: result, now: Date(), calendar: .current)
    }
}

/// WidgetKit calls `getSnapshot`/`getTimeline` with a completion handler that is not declared
/// `@Sendable`, and expects it called exactly once, from any thread. The glance is read in a task
/// (`SnapshotStore` is an actor), so this carries the handler across that one hop.
private struct OneShot<Value>: @unchecked Sendable {
    private let handler: (Value) -> Void
    init(_ handler: @escaping (Value) -> Void) { self.handler = handler }
    func callAsFunction(_ value: Value) { handler(value) }
}
