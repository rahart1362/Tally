import Foundation

/// ASC-14 "Explore with Sample Data": the bundled subset of `fixtures/canvas` (the flagship persona
/// and the 404 fallback), shipped as this target's `CanvasFixtures` resource, and the one way to
/// find it. TallyFeatures' `SampleDataFixtureBundle` reads it.
///
/// **Why a target of its own (plan 06 A2).** For every target with resources, SwiftPM and Xcode
/// generate an accessor file that declares `private class BundleFinder {}`. Inside TallyFeatures,
/// whose default isolation is `MainActor`, that class was given an isolated deinit, so the
/// TallyFeatures binary referenced `swift_task_deinitOnExecutor`, which CI's `nm` gate forbids
/// (run 36390172728). This target keeps Swift's default isolation (nonisolated), so its generated
/// accessor has no isolated deinit.
public enum SampleFixtures {
    /// The resource folder's name at the top level of this target's bundle.
    public static let folderName = "CanvasFixtures"

    /// The bundled fixtures folder, or `nil` if the bundle does not contain it.
    ///
    /// `.copy(_:)` places the folder, by name, at the bundle's top level (the `CpResource` line in
    /// CI run 36336754587), so the folder is asked for as a resource in its own right. The
    /// `resourceURL` join is the fallback, checked against the file system, in case a future
    /// SwiftPM or Xcode lays the bundle out differently.
    public static func folderURL() -> URL? {
        if let url = Bundle.module.url(forResource: folderName, withExtension: nil) {
            return url
        }
        if let base = Bundle.module.resourceURL {
            let candidate = base.appendingPathComponent(folderName)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
