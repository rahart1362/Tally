import Foundation
import Observation
import TallyDomain
import TallyStore

/// Settings' "What changed" threshold (owner decision DG-1, UX-WP-20): "All" or a point value,
/// globally and per course. Every change is written to `UserState.digestThresholds` through the
/// injected `UserStateAccess`; for a signed-in account that access also hands the thresholds to
/// the account's `RefreshCoordinator` (`updateDigestThresholds`).
///
/// Also "Show Grades in Widgets" (M2-C2 OI5): `UserState.showGradesInGlance`, off unless the student
/// turns it on (PMO R10). The account's coordinator reads it when it is built
/// (`AccountSessionFactory`), and each saved change reaches it at once
/// (`AccountUserStateAccess.update`: the glance on disk is rebuilt and the widget reloaded).
@MainActor
@Observable
public final class SettingsModel {
    /// Explicit and nonisolated (plan 06 A2; swiftlang/swift#88036).
    nonisolated deinit {}

    /// The point values the per-course menu offers, besides "All" and the global setting.
    public static let pointChoices: [Double] = [0.5, 1, 2, 5]
    /// The global stepper's range and step, in points.
    public static let pointRange: ClosedRange<Double> = 0.5...10
    public static let pointStep: Double = 0.5

    public private(set) var thresholds: DigestThresholds = .default
    /// `UserState.showGradesInGlance`.
    public private(set) var showGradesInWidgets = false
    public private(set) var hasLoaded = false
    /// The last threshold save failed (the file could not be written); the controls show what was
    /// asked for.
    public private(set) var saveFailed = false
    /// The same, for the widget setting.
    public private(set) var widgetSaveFailed = false
    /// M3-C (PMO R10, insights-at-a-glance.md §3.6): `UserState.hideCourseNamesInNotifications`.
    public private(set) var hideCourseNamesInNotifications = false
    /// The same, for the notification-names setting.
    public private(set) var hideCourseNamesSaveFailed = false

    private let userState: any UserStateAccess
    /// M3-C: runs a reminders pass once a notification setting is saved, so pending reminders are
    /// rewritten with the new words now rather than at the next refresh.
    private let notificationSettingsSaved: @MainActor () -> Void
    /// Saves run one after another, each writing the whole thresholds value, so the last change wins.
    @ObservationIgnored private var lastSave: Task<Void, Never>?

    public init(userState: any UserStateAccess, notificationSettingsSaved: @escaping @MainActor () -> Void = {}) {
        self.userState = userState
        self.notificationSettingsSaved = notificationSettingsSaved
    }

    public func load() async {
        guard !hasLoaded else { return }
        let state = await userState.load()
        thresholds = state.digestThresholds
        showGradesInWidgets = state.showGradesInGlance
        hideCourseNamesInNotifications = state.hideCourseNamesInNotifications
        hasLoaded = true
    }

    /// "Hide Course Names" in notifications on or off (R10): once saved, the pending reminders are
    /// rewritten ("a course", "An assignment").
    public func setHideCourseNamesInNotifications(_ hide: Bool) {
        guard hide != hideCourseNamesInNotifications else { return }
        hideCourseNamesInNotifications = hide
        save({ $0.hideCourseNamesInNotifications = hide }, failed: { model, failed in
            model.hideCourseNamesSaveFailed = failed
            if !failed { model.notificationSettingsSaved() }
        })
    }

    /// "Show Grades in Widgets" on or off.
    public func setShowGradesInWidgets(_ show: Bool) {
        guard show != showGradesInWidgets else { return }
        showGradesInWidgets = show
        save({ $0.showGradesInGlance = show }, failed: { model, failed in model.widgetSaveFailed = failed })
    }

    /// "Show every change" on (`.all`) or off (back to a point value).
    public func setEveryChange(_ everyChange: Bool) {
        let points = Self.points(of: thresholds.global) ?? TallyConfig.courseScoreChangeThreshold
        update { $0.global = everyChange ? .all : .points(points) }
    }

    /// The global point value (kept within `pointRange`).
    public func setGlobalPoints(_ points: Double) {
        let clamped = min(max(points, Self.pointRange.lowerBound), Self.pointRange.upperBound)
        update { $0.global = .points(clamped) }
    }

    /// One course's override; `nil` follows the global setting.
    public func setThreshold(_ threshold: ScoreChangeThreshold?, for course: CanvasID<Course>) {
        update { $0.perCourse[course] = threshold }
    }

    public static func points(of threshold: ScoreChangeThreshold) -> Double? {
        if case .points(let value) = threshold { return value }
        return nil
    }

    /// Waits for the saves in flight (tests).
    func awaitSaved() async {
        await lastSave?.value
    }

    private func update(_ change: (inout DigestThresholds) -> Void) {
        var changed = thresholds
        change(&changed)
        guard changed != thresholds else { return }
        thresholds = changed
        let saved = changed
        save({ $0.digestThresholds = saved }, failed: { model, failed in model.saveFailed = failed })
    }

    /// One save, after every save before it: each is a read-modify-write of the whole `UserState`,
    /// so two that overlapped could lose one change.
    private func save(_ change: @escaping @Sendable (inout UserState) -> Void,
                      failed: @escaping @MainActor (SettingsModel, Bool) -> Void) {
        let access = userState
        let previous = lastSave
        lastSave = Task { [weak self] in
            await previous?.value
            do {
                try await access.update(change)
                if let self { failed(self, false) }
            } catch {
                if let self { failed(self, true) }
            }
        }
    }
}
