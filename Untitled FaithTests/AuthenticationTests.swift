import AuthenticationServices
import CryptoKit
import XCTest
@testable import Untitled_Faith

final class AuthenticationTests: XCTestCase {
    func testAppleRequestsHaveUniqueStateAndHashedNonceWithNameScopeOnly() throws {
        let first = try AppleSignInAttempt()
        let second = try AppleSignInAttempt()
        XCTAssertEqual(first.nonce.count, 64)
        XCTAssertNotEqual(first.nonce, second.nonce)
        XCTAssertNotEqual(first.state, second.state)
        let request = ASAuthorizationAppleIDProvider().createRequest()
        first.configure(request)
        XCTAssertEqual(request.state, first.state)
        XCTAssertEqual(request.nonce, first.hashedNonce)
        XCTAssertNotEqual(request.nonce, first.nonce)
        XCTAssertEqual(request.requestedScopes, [.fullName])
    }

    func testRejectsUnsafeAuthenticationDestinations() {
        for value in ["http://faith.example", "file:///tmp/auth", "https://user:password@faith.example", "https://faith.example?token=secret", "https://faith.example#fragment"] {
            XCTAssertFalse(AuthenticationAPI.isSecureBaseURL(URL(string: value)!))
        }
        XCTAssertTrue(AuthenticationAPI.isSecureBaseURL(URL(string: "https://faith.example")!))
    }

    func testKeychainRoundTripAndRemoval() throws {
        let keychain = AuthenticationKeychain(service: "com.lukefournier.UntitledFaith.tests.\(UUID().uuidString)")
        defer { try? keychain.clear() }
        let stored = StoredAuthentication(appleUserID: "test-apple-user", apiBaseURL: URL(string: "https://faith.example")!, tokens: AuthenticationTokens(
            accessToken: "test-access", refreshToken: "sealed-test-refresh", expiresAt: Date().timeIntervalSince1970 + 900,
            sessionExpiresAt: Date().timeIntervalSince1970 + 86400
        ))
        XCTAssertNil(try keychain.load())
        try keychain.save(stored)
        XCTAssertEqual(try keychain.load()?.tokens.refreshToken, stored.tokens.refreshToken)
        XCTAssertEqual(try keychain.load()?.appleUserID, stored.appleUserID)
        try keychain.clear()
        XCTAssertNil(try keychain.load())
    }

    func testSessionExpiryAndRefreshWindow() {
        let now = Date().timeIntervalSince1970
        let nearlyExpired = AuthenticationTokens(accessToken: "a", refreshToken: "r", expiresAt: now + 30, sessionExpiresAt: now + 86400)
        XCTAssertTrue(nearlyExpired.needsRefresh)
        XCTAssertFalse(nearlyExpired.isExpired)
        let expired = AuthenticationTokens(accessToken: "a", refreshToken: "r", expiresAt: now - 1, sessionExpiresAt: now - 1)
        XCTAssertTrue(expired.isExpired)
    }
}
