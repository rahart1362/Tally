import WidgetKit

/// Abstraction over `WidgetCenter` so callers (and tests) don't depend on
/// WidgetKit directly (E03b). The post-commit pipeline (architecture.md
/// §3.4 step 1) calls `reloadTimelines(ofKind:)` only when the sealed
/// `glance` projection's hash actually changed.
public protocol WidgetReloading: Sendable {
    func reloadAllTimelines()
    func reloadTimelines(ofKind kind: String)
}

public struct WidgetReloader: WidgetReloading {
    public init() {}
    public func reloadAllTimelines() { WidgetCenter.shared.reloadAllTimelines() }
    public func reloadTimelines(ofKind kind: String) { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
}
