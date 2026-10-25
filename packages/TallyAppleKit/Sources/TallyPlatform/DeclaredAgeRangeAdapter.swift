#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif
import TallyDomain
import TallyFeatures
import UIKit

/// AGE-1 (EB-01): `AgeRangeService`. `#if canImport` keeps this file buildable if the framework
/// is ever absent from an SDK this project targets (TallyPlatform never compiles on Linux, so
/// this guards only against an unexpectedly old Xcode); `@available`/`#available` gate every call
/// to the OS version the symbol actually needs, which this project's own 26.0 floor (F16) is
/// below for several of them — see the deviations below, found only once this file compiled
/// against the real Xcode 26.6 SDK (`scope=only` runs 39609586767, 39615883368).
///
/// **API notes for the PMO (brief: "trust the SDK over the backlog if the APIs differ, and record
/// it").** Apple's own documentation pages render through JavaScript and returned only a title
/// when fetched as plain text from this host; this file was written from the **raw Markdown**
/// Apple serves at the same URL with a literal `.md` suffix (e.g.
/// `developer.apple.com/documentation/declaredagerange/agerangeservice.md`), which is the
/// authoritative symbol reference (declarations and Apple's own worked examples in "Requesting
/// people's age range information in your app" and "Implementing age assurance and permissions"
/// — both read in full), plus two rounds of real compiler feedback this Linux host cannot produce
/// itself (no Xcode):
/// 1. **`AgeRangeService.ParentalControls.significantAppChangeApprovalRequired` is deprecated.**
///    The current signal is `AgeRangeService.requiredRegulatoryFeatures` (iOS 26.4+), a
///    `Set<RegulatoryFeature>`; this file prefers it and falls back to the deprecated flag only
///    below 26.4 (both floors sit at or above 26.2, this project's own floor stays 26.0 — F16).
/// 2. **`isEligibleForAgeFeatures` and `requiredRegulatoryFeatures` each need iOS 26.2+**, not the
///    26.0 their enclosing type's framework-level availability block suggested; the docs' member
///    list did not carry each member's own floor. `significantAppChangeApprovalRequired` needs
///    26.2 too (run 39615883368's compiler errors, not the docs, established this).
/// 3. **Both async properties are `nonisolated` on a non-Sendable `AgeRangeService`.** Calling
///    either directly from this `@MainActor` class (needed for `requestAgeRange(ageGates:in:)`
///    and `UIApplication.shared`, both UI-presentation calls) failed to compile: "non-Sendable
///    type 'AgeRangeService' cannot exit main actor-isolated context in call to nonisolated
///    property" (run 39615883368). Each is wrapped in a small `nonisolated` static function
///    below (`isEligibleForAgeFeatures()`, `regulatoryFeatureFlags()`) that reads the property
///    and extracts only `Sendable` `Bool`s before returning — the non-Sendable `AgeRangeService`
///    value, and the not-provably-Sendable `Set<RegulatoryFeature>`, never cross back out of that
///    nonisolated context at all.
@MainActor
public final class DeclaredAgeRangeAdapter: AgeAssuranceRequesting {
    public init() {}

    public func requestAgeAssurance() async -> AgeAssuranceOutcome {
        #if canImport(DeclaredAgeRange)
        // AGE-2: every path below that never actually presented the system sheet (the OS floor,
        // no window, a thrown error, or an SDK response this adapter cannot interpret) is
        // `.unavailable`, never `.declined` — only `Response.declinedSharing`, an answer the
        // person actually gave, is a decline.
        guard #available(iOS 26.2, *) else { return .unavailable }
        guard let viewController = Self.presentationController() else { return .unavailable }
        guard await Self.isEligibleForAgeFeatures() else { return .regulatoryRequirementsDoNotApply }
        do {
            // EB-01(b): the four TX/UT/AL/LA categories (child <13, younger teen 13-15, older teen
            // 16-17, adult) are exactly the three gates 13/16/18 produce.
            let response = try await AgeRangeService.shared.requestAgeRange(ageGates: 13, 16, 18, in: viewController)
            switch response {
            case .declinedSharing:
                return .declined
            case .sharing(let range):
                let category = AgeCategory.fromLowerBound(range.lowerBound)
                let requirement = await Self.significantChangeRequirement(for: category, range: range)
                return .shared(AgeAssuranceSignal(category: category, significantChangeRequirement: requirement))
            @unknown default:
                return .unavailable
            }
        } catch {
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    #if canImport(DeclaredAgeRange)
    /// See API note 3 above: wrapped so the non-Sendable `AgeRangeService` value this nonisolated
    /// property access touches never has to cross back into the caller's `@MainActor` context —
    /// only the `Bool` result does, and `Bool` is `Sendable`.
    @available(iOS 26.2, *)
    nonisolated private static func isEligibleForAgeFeatures() async -> Bool {
        (try? await AgeRangeService.shared.isEligibleForAgeFeatures) ?? false
    }

    /// EB-02: which significant-change duties apply to this person, preferring the current
    /// (26.4+) `requiredRegulatoryFeatures` and falling back to the deprecated per-response
    /// `ParentalControls` flag below that (both reachable: this project's own floor is 26.0, and
    /// both need at least 26.2 — see API notes 1/2 above). A non-minor never needs parental
    /// consent regardless of what either signal says (`AgeCategory.isMinor`); the
    /// adult-notification duty is independent of category and is read from the same source.
    @available(iOS 26.2, *)
    private static func significantChangeRequirement(for category: AgeCategory,
                                                       range: AgeRangeService.AgeRange) async -> SignificantChangeRequirement {
        if #available(iOS 26.4, *), let flags = await Self.regulatoryFeatureFlags() {
            return SignificantChangeRequirement(
                parentalConsentRequired: category.isMinor && flags.parentalConsentRequired,
                adultNotificationRequired: flags.adultNotificationRequired)
        }
        // iOS 26.2–26.3: no adult-notification signal existed yet; only the minor flag did.
        let legacyFlagSet = range.activeParentalControls.contains(.significantAppChangeApprovalRequired)
        return SignificantChangeRequirement(parentalConsentRequired: category.isMinor && legacyFlagSet,
                                            adultNotificationRequired: false)
    }

    /// See API note 3 above: extracts only `Bool`s from `Set<RegulatoryFeature>` before returning,
    /// so neither the non-Sendable `AgeRangeService` receiver nor the not-provably-`Sendable` set
    /// itself ever crosses back into the caller's `@MainActor` context.
    @available(iOS 26.4, *)
    nonisolated private static func regulatoryFeatureFlags() async
        -> (parentalConsentRequired: Bool, adultNotificationRequired: Bool)? {
        guard let features = try? await AgeRangeService.shared.requiredRegulatoryFeatures else { return nil }
        return (features.contains(.significantAppChangeRequiresParentalConsent),
                features.contains(.significantAppChangeRequiresAdultNotification))
    }
    #endif

    @MainActor
    private static func presentationController() -> UIViewController? {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene,
               let window = windowScene.windows.first(where: \.isKeyWindow) {
                return window.rootViewController
            }
        }
        return nil
    }
}
