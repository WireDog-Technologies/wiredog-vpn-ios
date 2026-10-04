import Foundation

// Native SAML SSO for Business employees. The app opens the backend's /auth/sso/login in an
// ASWebAuthenticationSession; the backend bounces to the org's IdP, validates the assertion, and
// redirects to wiredog://sso?code=... (or ?error=...). That code is bound to a PKCE challenge
// generated here, so another app that registers the same URL scheme and sees the code cannot
// redeem it: only the verifier, which never leaves this process, completes the exchange.
// Backend counterpart: wiredog-backend/src/routes/auth.ts (/sso/login, /sso/acs, /sso/exchange).

#if os(iOS)
import AuthenticationServices
import CryptoKit
import Security
import UIKit

@MainActor
final class SSOService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = SSOService()

    enum SSOError: Error {
        case cancelled
        case noAccount
        case failed
    }

    struct Credentials {
        let code: String
        let codeVerifier: String
    }

    // Must match APP_SSO_CALLBACK in the backend's routes/auth.ts. ASWebAuthenticationSession
    // intercepts this scheme itself, so it does not need to be registered in Info.plist.
    private static let callbackScheme = "wiredog"

    // Held only while a session is on screen.
    private var session: ASWebAuthenticationSession?

    func authenticate(domain: String) async throws -> Credentials {
        let verifier = Self.makeCodeVerifier()

        guard var components = URLComponents(
            url: Config.apiBaseURL.appendingPathComponent("auth/sso/login"),
            resolvingAgainstBaseURL: false
        ) else { throw SSOError.failed }
        components.queryItems = [
            URLQueryItem(name: "domain", value: domain),
            URLQueryItem(name: "challenge", value: Self.codeChallenge(for: verifier)),
        ]
        guard let startURL = components.url else { throw SSOError.failed }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: startURL,
                callbackURLScheme: Self.callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let authError = error as? ASWebAuthenticationSessionError,
                          authError.code == .canceledLogin {
                    continuation.resume(throwing: SSOError.cancelled)
                } else {
                    continuation.resume(throwing: SSOError.failed)
                }
            }
            session.presentationContextProvider = self
            // Not ephemeral: sharing Safari's cookies lets an employee already signed in to their
            // IdP skip its login page, which is the point of SSO.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: SSOError.failed)
            }
        }
        session = nil

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let reason = items.first(where: { $0.name == "error" })?.value {
            throw reason == "sso_no_account" ? SSOError.noAccount : SSOError.failed
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, code.count == 64 else {
            throw SSOError.failed
        }
        return Credentials(code: code, codeVerifier: verifier)
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }

    // MARK: - PKCE (RFC 7636, S256)

    /// 43 base64url characters from 32 random bytes.
    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return base64URL(Data(bytes))
    }

    static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
#else
// tvOS signs in through device pairing (the phone or website handles SSO), and has no
// ASWebAuthenticationSession. This stub keeps the shared AuthService compiling there.
@MainActor
final class SSOService {
    static let shared = SSOService()

    enum SSOError: Error {
        case cancelled
        case noAccount
        case failed
    }

    struct Credentials {
        let code: String
        let codeVerifier: String
    }

    func authenticate(domain: String) async throws -> Credentials {
        throw SSOError.failed
    }
}
#endif
