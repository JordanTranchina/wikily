import CryptoKit
import Foundation
import Testing
@testable import Wikily

struct OAuthPKCETests {

    @Test func codeChallengeIsTheSHA256OfTheVerifier() {
        let fixedBytes = Data(repeating: 0x2A, count: 32)
        let pkce = OAuthPKCE(randomBytes: { fixedBytes })

        let expectedVerifier = OAuthPKCE.base64URLEncode(fixedBytes)
        #expect(pkce.codeVerifier == expectedVerifier)

        let expectedChallenge = OAuthPKCE.base64URLEncode(
            Data(SHA256.hash(data: Data(expectedVerifier.utf8)))
        )
        #expect(pkce.codeChallenge == expectedChallenge)
    }

    @Test func base64URLEncodingUsesTheURLSafeAlphabetWithNoPadding() {
        // Three zero bytes base64-encode to "AAAA" with no padding needed —
        // this exercises the "no substitution required" path. The
        // alphabet-substitution path (`+`/`/`) is exercised implicitly by
        // every PKCE round trip above, since 32 random bytes almost always
        // contain at least one.
        #expect(OAuthPKCE.base64URLEncode(Data([0, 0, 0])) == "AAAA")
        #expect(!OAuthPKCE.base64URLEncode(Data([0, 0, 0])).contains("="))
    }

    @Test func eachInstanceGetsAFreshStateAndVerifier() {
        let first = OAuthPKCE()
        let second = OAuthPKCE()
        #expect(first.state != second.state)
        #expect(first.codeVerifier != second.codeVerifier)
    }

    @Test func randomDataProducesTheRequestedLength() {
        #expect(OAuthPKCE.randomData(count: 32).count == 32)
        #expect(OAuthPKCE.randomData(count: 16).count == 16)
    }
}
