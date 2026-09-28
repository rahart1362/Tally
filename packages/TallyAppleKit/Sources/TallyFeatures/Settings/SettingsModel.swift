import Foundation
import Observation
import TallyDomain
import TallyStore

/// Settings' "What changed" threshold (owner decision DG-1, UX-WP-20): "All" or a point value,
/// globally and per course. Every change is written to `UserState.digestThresholds` through the
/// injected `UserStateAccess`; for a signed-in account that access also hands the thresholds to
/// the account's `RefreshCoordinator` (`updateDigestThresholds`).
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
    public private(set) var hasLoaded = false
    /// The last save failed (the file could not be written); the controls show what was asked for.
    public private(set) var saveFailed = false

    private let userState: any UserStateAccess
    /// Saves run one after another, each writing the whole thresholds value, so the last change wins.
    @ObservationIgnored private var lastSave: Task<Void, Never>?

    public init(userState: any UserStateAccess) {
        self.userState = userState
    }

    public func load() async {
        guard !hasLoaded else { return }
        thresholds = await userState.load().digestThresholds
        hasLoaded = true
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
        let access = userState
        let previous = lastSave
        lastSave = Task { [weak self] in
            await previous?.value
            do {
                try await access.update { $0.digestThresholds = saved }
                self?.saveFailed = false
            } catch {
                self?.saveFailed = true
            }
        }
    }
}
