import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import TallyDomain

/// SEC1-05 (RFC 9700 §4.4.2's mix-up defence): Canvas sends no `iss` parameter on the callback, so
/// nothing in the OAuth response itself says which authorization server actually answered. A
/// distinct redirect URI per institution is the alternative defence RFC 9700 names, and
/// `OAuthCallback.code(from:for:now:)` already requires the callback's path to equal
/// `AuthorizationRequest.redirectURI`'s path exactly -- so binding each institution's redirect to
/// its own path (`SignInHandoffViewModel.redirectURI(forHost:)`) is enough on its own: a callback
/// delivered for one institution's session can never validate against another's request, because
/// their paths differ.
public enum InstitutionID {
    /// A stable, opaque id for `host`, never the host itself: a URL path segment can end up in
    /// system logs (`ASWebAuthenticationSession`, or a web server if the static fallback page at
    /// `site/oauth/callback/` is ever actually hit) the same way `AccountKey.derive` keeps a
    /// Canvas host out of a notification ID. Deterministic, so the same host always redirects to
    /// the same path -- callers never need to persist this anywhere.
    public static func derive(host: String) -> String {
        let digest = SHA256.hash(data: Data(host.lowercased().utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(TallyConfig.institutionIdHexLength))
    }
}
