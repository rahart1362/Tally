import Foundation
import AuthenticationServices
import CryptoKit
import TallySecurity

public class CanvasOAuthManager: NSObject {
    private let clientId: String
    private let redirectUri: String
    private let baseURL: URL
    
    public init(clientId: String, redirectUri: String, baseURL: URL) {
        self.clientId = clientId
        self.redirectUri = redirectUri
        self.baseURL = baseURL
    }
    
    public func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    public func generateCodeChallenge(verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    public func startAuthFlow(presentationContextProvider: ASWebAuthenticationPresentationContextProviding) async throws -> String {
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(verifier: verifier)
        
        var components = URLComponents(url: baseURL.appendingPathComponent("login/oauth2/auth"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        guard let authURL = components.url else {
            throw URLError(.badURL)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "tally") { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: URLError(.cannotParseResponse))
                    return
                }
                
                // Note: Normally we'd exchange code for token here, passing the verifier
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = presentationContextProvider
            session.start()
        }
    }
}
