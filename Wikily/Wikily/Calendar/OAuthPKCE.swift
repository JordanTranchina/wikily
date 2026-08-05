import CryptoKit
import Foundation

/// RFC 7636 PKCE values for one authorization attempt, plus a CSRF `state`.
///
/// Both Google and Microsoft support PKCE for public clients — no client
/// secret — which is what makes it possible for a native, source-available app
/// to ship an OAuth flow at all: a secret embedded in an app anyone can
/// disassemble was never a secret. `state` rides along because it's the other
/// mandatory piece of an authorization-code flow, checked against the
/// callback in `CalendarAccountStore.code(from:expectedState:)`.
struct OAuthPKCE: Sendable {
    let codeVerifier: String
    let codeChallenge: String
    let state: String

    /// - Parameter randomBytes: injected so tests can assert the challenge is
    ///   the correct SHA-256 of a *known* verifier, instead of only asserting
    ///   "it round-trips".
    init(randomBytes: () -> Data = { OAuthPKCE.randomData(count: 32) }) {
        let verifierBytes = randomBytes()
        codeVerifier = Self.base64URLEncode(verifierBytes)
        codeChallenge = Self.base64URLEncode(Data(SHA256.hash(data: Data(codeVerifier.utf8))))
        state = Self.base64URLEncode(Self.randomData(count: 16))
    }

    static func randomData(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max) })
    }

    /// RFC 4648 §5 — the URL- and filename-safe alphabet PKCE requires,
    /// padding stripped.
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
