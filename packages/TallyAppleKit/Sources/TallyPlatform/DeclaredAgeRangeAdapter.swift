#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif
import TallyDomain
import TallyFeatures
import UIKit

/// AGE-1 (EB-01): `AgeRangeService` (iOS 26.0+; entitlement `com.apple.developer.declared-age-range`,
/// already allow-listed by `check_release.py`'s `ENTITLEMENTS_ALLOWED`). `#if canImport` keeps this
/// file buildable if the framework is ever absent from an SDK this project targets (TallyPlatform
/// never compiles on Linux, so this guards only against an unexpectedly old Xcode); `@available`
/// keeps every call gated to the OS version the symbol actually needs, since the project's floor
/// (iOS 26.0, F16) is below the 26.4 floor `requiredRegulatoryFeatures` needs.
///
/// **API note for the PMO (brief: "trust the SDK over the backlog if the APIs differ, and record
/// it").** Apple's own documentation pages render through JavaScript and returned only a title
/// when fetched as plain text from this host; this file was written from the **raw Markdown**
/// Apple serves at the same URL with a literal `.md` suffix (e.g.
/// `developer.apple.com/documentation/declaredagerange/agerangeservice.md`), which is the
/// authoritative symbol reference (declarations, availability, and Apple's own worked examples in
/// "Requesting people's age range information in your app" and "Implementing age assurance and
/// permissions" — both read in full). Two deviations from the backlog's assumption, both already
/// recorded here and in the PR:
/// 1. **`AgeRangeService.ParentalControls.significantAppChangeApprovalRequired` is deprecated.**
///    The current signal is `AgeRangeService.requiredRegulatoryFeatures` (iOS 26.4+), a
///    `Set<RegulatoryFeature>`; this file prefers it and falls back to the deprecated flag only
///    below 26.4, which this project's 26.0 floor can still reach.
/// 2. **`isEligibleForAgeFeatures`'s own symbol page shows a plain `Bool`, but every one of
///    Apple's worked examples calls it as `try await ...isEligibleForAgeFeatures`.** Written as
///    `try await` here, matching the worked examples; if the real Xcode 26.6 SDK disagrees, the
///    first `scope=only` CI run fails to compile and this is where to fix it.
///
/// This file has not compiled against the real SDK — this host has no Xcode. The first
/// `scope=only` run is where that happens.
@MainActor
public final class DeclaredAgeRangeAdapter: AgeAssuranceRequesting {
    public init() {}

    public func requestAgeAssurance() async -> AgeAssuranceOutcome {
        #if canImport(DeclaredAgeRange)
        guard let viewController = Self.presentationController() else { return .declinedOrUnavailable }
        do {
            guard try await AgeRangeService.shared.isEligibleForAgeFeatures else {
                return .regulatoryRequirementsDoNotApply
            }
            // EB-01(b): the four TX/UT/AL/LA categories (child <13, younger teen 13-15, older teen
            // 16-17, adult) are exactly the three gates 13/16/18 produce.
            let response = try await AgeRangeService.shared.requestAgeRange(ageGates: 13, 16, 18, in: viewController)
            switch response {
            case .declinedSharing:
                return .declinedOrUnavailable
            case .sharing(let range):
                let category = AgeCategory.fromLowerBound(range.lowerBound)
                let requirement = await Self.significantChangeRequirement(for: category, range: range)
                return .shared(AgeAssuranceSignal(category: category, significantChangeRequirement: requirement))
            @unknown default:
                return .declinedOrUnavailable
            }
        } catch {
            return .declinedOrUnavailable
        }
        #else
        return .declinedOrUnavailable
        #endif
    }

    #if canImport(DeclaredAgeRange)
    /// EB-02: which significant-change duties apply to this person, preferring the current
    /// (26.4+) `requiredRegulatoryFeatures` and falling back to the deprecated per-response
    /// `ParentalControls` flag below that — see the API note above. A non-minor never needs
    /// parental consent regardless of what either signal says (`AgeCategory.isMinor`): the
    /// adult-notification duty is independent of category and is read from the same source.
    private static func significantChangeRequirement(for category: AgeCategory,
                                                       range: AgeRangeService.AgeRange) async -> SignificantChangeRequirement {
        if #available(iOS 26.4, *), let features = try? await AgeRangeService.shared.requiredRegulatoryFeatures {
            return SignificantChangeRequirement(
                parentalConsentRequired: category.isMinor && features.contains(.significantAppChangeRequiresParentalConsent),
                adultNotificationRequired: features.contains(.significantAppChangeRequiresAdultNotification))
        }
        // iOS 26.0–26.3: no adult-notification signal existed yet; only the minor flag did.
        let legacyFlagSet = range.activeParentalControls.contains(.significantAppChangeApprovalRequired)
        return SignificantChangeRequirement(parentalConsentRequired: category.isMinor && legacyFlagSet,
                                            adultNotificationRequired: false)
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
