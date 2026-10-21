#if canImport(PermissionKit)
import PermissionKit
#endif
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif
import TallyDomain
import TallyFeatures
import UIKit

/// AGE-1 (EB-02(b)): PermissionKit's `SignificantAppUpdateTopic`/`AskCenter` for an affected minor,
/// and DeclaredAgeRange's own `showSignificantUpdateAcknowledgment` for a verified adult who only
/// needs to be notified. Written from the raw Markdown Apple serves at
/// `developer.apple.com/documentation/permissionkit/*.md` and
/// `.../declaredagerange/implementing-age-assurance-and-permissions.md` (see the API note in
/// `DeclaredAgeRangeAdapter.swift`); not yet compiled against the real SDK.
@MainActor
public final class SignificantChangeConsentAdapter: SignificantChangeConsenting {
    public init() {}

    public func requestConsent(changeDescription: String, for requirement: SignificantChangeRequirement) async -> SignificantChangeConsentOutcome {
        guard requirement.isAny else { return .notRequired }
        #if canImport(PermissionKit)
        if requirement.parentalConsentRequired {
            guard #available(iOS 26.2, *), let viewController = Self.presentationController() else { return .unavailable }
            let topic = SignificantAppUpdateTopic(description: changeDescription)
            let question = PermissionQuestion(significantAppUpdateTopic: topic)
            do {
                // `ask(_:in:)`: hands the question to the system and returns once it has been
                // sent; the parent's eventual answer arrives separately through
                // `AskCenter.responses(for:)` (`pendingAnswers()` below), matched by topic.
                try await AskCenter.shared.ask(question, in: viewController)
                return .pending
            } catch {
                return .unavailable
            }
        }
        #endif
        #if canImport(DeclaredAgeRange)
        if requirement.adultNotificationRequired {
            guard let scene = Self.windowScene() else { return .unavailable }
            do {
                try await AgeRangeService.shared.showSignificantUpdateAcknowledgment(in: scene, updateDescription: changeDescription)
                return .granted
            } catch {
                return .unavailable
            }
        }
        #endif
        return .unavailable
    }

    public func pendingAnswers() -> AsyncStream<SignificantChangeConsentOutcome> {
        #if canImport(PermissionKit)
        guard #available(iOS 26.2, *) else { return AsyncStream { $0.finish() } }
        return AsyncStream { continuation in
            let task = Task {
                for await response in AskCenter.shared.responses(for: SignificantAppUpdateTopic.self) {
                    // `PermissionChoice.approve`/`.decline` set `answer` to `.approval`/`.denial`
                    // (PermissionKit's own two system-preferred choices); this app offers no
                    // custom choices, so those are the only two that can arrive here.
                    continuation.yield(response.choice.answer == .approval ? .granted : .denied)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        #else
        return AsyncStream { $0.finish() }
        #endif
    }

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

    @MainActor
    private static func windowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene
    }
}
