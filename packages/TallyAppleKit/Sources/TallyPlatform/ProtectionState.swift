import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Architecture's proposed contract for whether Data Protection has
/// unlocked CUFA-class files and Keychain items (architecture.md §3.2:
/// "Interface to the Encryption specialist" — `SnapshotSealer` /
/// `ProtectionStateProviding`). This exact protocol has not yet been added
/// to `packages/TallyCore` (it is architecture.md's own sketch, not a
/// merged port), so it is defined here in `TallyPlatform` rather than
/// edited into the read-only `TallyCore` package — flagged for the PMO:
/// once `TallyStore`/`TallySync` want to gate a locked-read retry on this
/// signal, this protocol (or an equivalent) should move to `TallyDomain` so
/// both sides of the Linux boundary can depend on it.
public protocol ProtectionStateProviding: Sendable {
    var isProtectedDataAvailable: Bool { get async }
}

/// `UIApplication.isProtectedDataAvailable` (E03b). `UIApplication` is
/// main-actor isolated, hence the hop.
public struct ProtectionState: ProtectionStateProviding {
    public init() {}

    public var isProtectedDataAvailable: Bool {
        get async {
            #if canImport(UIKit)
            await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
            #else
            true
            #endif
        }
    }
}
