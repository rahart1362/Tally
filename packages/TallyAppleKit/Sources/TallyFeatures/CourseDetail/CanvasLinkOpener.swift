import TallyCanvasAPI
import UIKit

/// Opens a Canvas page for "Open in Canvas" (PMO R20): the Canvas Student app when it is
/// installed (`CanvasLink.appURL`) and the student's preference (FEAT-8, Idea 7) allows it,
/// otherwise the browser. The student's own tap is the only way Tally leaves for Canvas (R16:
/// Tally never writes to Canvas itself).
///
/// SEC1-15: `web` comes from Canvas-supplied data (an assignment, calendar-event or planner
/// `html_url`), never rebuilt by Tally, so a compromised or malicious Canvas instance could in
/// principle point it anywhere. `open` only ever opens an `https` URL on the signed-in account's
/// own Canvas host (or that host's Canvas Student app mapping, `CanvasLink.appURL`, which is
/// derived from the same validated URL and so is always on the same host too); anything else is
/// not opened, silently — no new string. `isSafe` runs first in every mode: the preference below
/// only ever picks among destinations that already passed it.
enum CanvasLinkOpener {
    static func open(_ web: URL, accountHost: String, preference: CanvasLinkPreference = .app) async {
        guard isSafe(web, accountHost: accountHost) else { return }
        for destination in destinations(for: web, preference: preference) {
            if await UIApplication.shared.open(destination) { return }
        }
    }

    /// Pure, for testing: which URL(s) to try, in order, for a link `isSafe` has already cleared.
    /// `.app` tries the Canvas Student app mapping first, then falls back to the browser (today's
    /// default, R20, unchanged); `.browser` never tries the app.
    nonisolated static func destinations(for web: URL, preference: CanvasLinkPreference) -> [URL] {
        switch preference {
        case .app:
            if let app = CanvasLink.appURL(for: web) { return [app, web] }
            return [web]
        case .browser:
            return [web]
        }
    }

    /// Pure, for testing: reuses the same host policy the network layer applies before it attaches
    /// a bearer token to a URL (`PageURLPolicy.validate`, security.md WP-SEC-08), so "safe to open"
    /// and "safe to attach a token to" can never drift apart. `https` only, no embedded userinfo,
    /// and the host must be `accountHost` (port 443 or none).
    nonisolated static func isSafe(_ web: URL, accountHost: String) -> Bool {
        guard !accountHost.isEmpty else { return false }
        do {
            try PageURLPolicy.validate(web, allowedHosts: [accountHost])
            return true
        } catch {
            return false
        }
    }
}
