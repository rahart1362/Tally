import Foundation

/// Idea 9 (ideas1 report, "Handoff to Mac/iPad browser from an assignment"): Handoff to the
/// companion device's default browser, continuing on the same `webpageURL` "Open in Canvas"
/// already opens — never to another copy of Tally. A non-nil `webpageURL` on `NSUserActivity` asks
/// the system to offer that continuation in the browser directly; unlike continuing in another
/// app, this needs no activity type declared in Info.plist, so `activityType` below exists only to
/// identify the activity to this app and to `NSUserActivity` itself, following the same
/// `Bundle.main.bundleIdentifier + ".<suffix>"` convention as `BackgroundRefresh`'s identifier and
/// `KeychainEntitlementStore`'s service name.
nonisolated enum CanvasHandoffActivity {
    static let activityType = (Bundle.main.bundleIdentifier ?? "dev.tally-app.tally") + ".canvas-page"

    /// Pure: the `webpageURL` Handoff should publish right now, or `nil` when it should not be
    /// offered — sample mode (ASC-14: no real Canvas to continue to, so no Handoff for sample
    /// data) or a `web` that fails the same host check "Open in Canvas" uses
    /// (`CanvasLinkOpener.isSafe`), so the two can never disagree about what is safe to hand to the
    /// system. Returning `nil` is also how Handoff is invalidated: the `.userActivity(_:element:_:)`
    /// modifier retires a previously published activity once its element goes `nil`, and the
    /// signed-in route's views (where this is attached) go away entirely on sign-out
    /// (`AppModel.signOut()`'s first step switches `route` away from `.signedIn`), which tears the
    /// modifier down with them.
    static func webpageURL(for web: URL?, accountHost: String, isSampleData: Bool) -> URL? {
        guard let web, CanvasLinkOpener.isSafe(web, accountHost: accountHost) else { return nil } // MUTATION: isSampleData guard dropped
        return web
    }

    /// Configures a freshly created `NSUserActivity`: eligible for Handoff only, never Spotlight
    /// search or Siri's prediction (idea 9's scope — a one-off continuation, not a suggestion).
    static func configure(_ activity: NSUserActivity, webpageURL: URL) {
        activity.isEligibleForSearch = false
        activity.isEligibleForPrediction = false
        activity.webpageURL = webpageURL
    }
}
