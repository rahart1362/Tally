import UIKit

/// Opens a Canvas page for "Open in Canvas" (PMO R20): the Canvas Student app when it is installed
/// (`CanvasLink.appURL`), otherwise the browser. The student's own tap is the only way Tally leaves
/// for Canvas (R16: Tally never writes to Canvas itself).
enum CanvasLinkOpener {
    static func open(_ web: URL) async {
        if let app = CanvasLink.appURL(for: web), await UIApplication.shared.open(app) { return }
        await UIApplication.shared.open(web)
    }
}
