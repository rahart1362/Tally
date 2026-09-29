import Foundation

/// PMO R20 / integrations.md §2.1: "Open in Canvas" tries the Canvas Student app first and always
/// falls back to the web. The app registers the `canvas-courses` scheme and its router rewrites
/// `canvas-courses://<host>/<path>` to `https://<host>/<path>` (Instructure's open-source canvas-ios);
/// schools' `apple-app-site-association` files do not route assignment URLs to the app. The scheme
/// is not a published contract (backlog BL-19), so the web fallback is mandatory.
nonisolated enum CanvasLink {
    /// `https://host/path?query` as `canvas-courses://host/path?query`; `nil` for anything that is
    /// not an http(s) URL with a host.
    static func appURL(for web: URL) -> URL? {
        guard var components = URLComponents(url: web, resolvingAgainstBaseURL: false),
              components.scheme == "https" || components.scheme == "http",
              let host = components.host, !host.isEmpty else { return nil }
        components.scheme = "canvas-courses"
        return components.url
    }
}
