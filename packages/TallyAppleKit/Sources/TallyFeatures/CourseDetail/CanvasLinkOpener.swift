import TallyCanvasAPI
import UIKit

/// Opens a Canvas page for "Open in Canvas" (PMO R20): the Canvas Student app when it is installed
/// (`CanvasLink.appURL`), otherwise the browser. The student's own tap is the only way Tally leaves
/// for Canvas (R16: Tally never writes to Canvas itself).
///
/// SEC1-15: `web` comes from Canvas-supplied data (an assignment, calendar-event or planner
/// `html_url`), never rebuilt by Tally, so a compromised or malicious Canvas instance could in
/// principle point it anywhere. `open` only ever opens an `https` URL on the signed-in account's
/// own Canvas host (or that host's Canvas Student app mapping, `CanvasLink.appURL`, which is
/// derived from the same validated URL and so is always on the same host too); anything else is
/// not opened, silently — no new string.
enum CanvasLinkOpener {
    static func open(_ web: URL, accountHost: String) async {
        guard isSafe(web, accountHost: accountHost) else { return }
        if let app = CanvasLink.appURL(for: web), await UIApplication.shared.open(app) { return }
        await UIApplication.shared.open(web)
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
