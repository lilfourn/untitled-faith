import AuthenticationServices
import XCTest
@testable import Untitled_Faith

@MainActor
final class SessionRecoveryTests: XCTestCase {
    private let base = URL(string: "https://session-tests.example")!

    private func stored(expired: Bool = false) -> StoredAuthentication {
        StoredAuthentication(appleUserID: UUID().uuidString, apiBaseURL: base,
            tokens: AuthenticationTokens(accessToken: "old-access", refreshToken: "sealed-refresh",
                expiresAt: Date().timeIntervalSince1970 - 10,
                sessionExpiresAt: Date().timeIntervalSince1970 + (expired ? -1 : 86400)))
    }

    private func api() -> AuthenticationAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionURLProtocol.self]
        return AuthenticationAPI(baseURL: base, session: URLSession(configuration: configuration))
    }

    private func preferences() -> UserDefaults { UserDefaults(suiteName: "session-tests.\(UUID())")! }

    func testCredentialLookupOutagePreservesRecordAndAllowsRestorationRetry() async throws {
        let record = MemoryRecord(stored())
        var unavailable = true
        var attempts = 0
        SessionURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let session = AppSession(preferences: preferences(), api: api(), keychain: record,
            deletionStorage: MemoryRecord<PendingAccountDeletion>(nil), credentialState: { _ in
                attempts += 1
                if unavailable { throw URLError(.notConnectedToInternet) }
                return .authorized
            })
        await session.restoreSession()
        XCTAssertFalse(session.isSignedIn)
        XCTAssertTrue(session.canRetryRestoration)
        XCTAssertNotNil(record.value)
        unavailable = false
        await session.restoreSession(retry: true)
        XCTAssertEqual(attempts, 2)
        // Credential lookup recovered. A failed token refresh still retains the local account.
        XCTAssertTrue(session.isSignedIn)
        XCTAssertTrue(session.canRetryRestoration)
        XCTAssertNotNil(record.value)
        session.signOut()
    }

    func testRefreshOutageThenReconnectRecoversWithoutAppleAuthorization() async throws {
        let record = MemoryRecord(stored())
        var unavailable = true
        SessionURLProtocol.handler = { request in
            guard request.url?.path == "/v1/auth/refresh" else { return (503, Data()) }
            if unavailable { throw URLError(.notConnectedToInternet) }
            let now = Date().timeIntervalSince1970
            return (200, try JSONEncoder().encode(AuthenticationTokens(accessToken: "new-access", refreshToken: "new-sealed-refresh",
                expiresAt: now + 899, sessionExpiresAt: now + 86400)))
        }
        let session = AppSession(preferences: preferences(), api: api(), keychain: record,
            deletionStorage: MemoryRecord<PendingAccountDeletion>(nil), credentialState: { _ in .authorized })
        await session.restoreSession()
        XCTAssertTrue(session.canRetryRestoration)
        XCTAssertEqual(record.value?.tokens.accessToken, "old-access")
        unavailable = false
        await session.restoreSession(retry: true)
        XCTAssertFalse(session.canRetryRestoration)
        XCTAssertTrue(session.isSignedIn)
        XCTAssertEqual(record.value?.tokens.accessToken, "new-access")
        session.signOut()
    }

    func testExpiredAndRevokedCredentialsDoNotBecomeRecoverableSessions() async {
        for expired in [true, false] {
            let record = MemoryRecord(stored(expired: expired))
            let session = AppSession(preferences: preferences(), api: api(), keychain: record,
                deletionStorage: MemoryRecord<PendingAccountDeletion>(nil), credentialState: { _ in .revoked })
            await session.restoreSession()
            XCTAssertFalse(session.isSignedIn)
            XCTAssertFalse(session.canRetryRestoration)
            XCTAssertNil(record.value)
        }
    }

    func testRejectedRenewalRequiresSignInInsteadOfEndlessRetries() async {
        SessionURLProtocol.handler = { _ in (401, Data()) }
        let record = MemoryRecord(stored())
        let session = AppSession(preferences: preferences(), api: api(), keychain: record,
            deletionStorage: MemoryRecord<PendingAccountDeletion>(nil), credentialState: { _ in .authorized })
        await session.restoreSession()
        XCTAssertFalse(session.isSignedIn)
        XCTAssertFalse(session.canRetryRestoration)
        XCTAssertNil(record.value)
    }

    func testPendingDeletionSurvivesLostResponseAndCleansOnlyItsOwnAccountOnRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = stored()
        let intent = PendingAccountDeletion(authentication: original)
        let pending = MemoryRecord<PendingAccountDeletion>(intent)
        let record = MemoryRecord(original)
        let own = LocalConversationStorage(namespace: intent.namespace, root: root)
        let other = LocalConversationStorage(namespace: "another-account", root: root)
        var chat = Conversation()
        chat.messages = [.question(id: UUID(), text: "Saved")]
        try own.save(chat)
        try other.save(chat)
        SessionURLProtocol.handler = { _ in throw URLError(.networkConnectionLost) }
        let first = AppSession(preferences: preferences(), api: api(), keychain: record, storageRoot: root,
            deletionStorage: pending, credentialState: { _ in XCTFail("Deletion must precede Apple credential checks"); return .revoked })
        await first.restoreSession()
        XCTAssertTrue(first.hasPendingDeletion)
        XCTAssertFalse(first.canSignIn)
        XCTAssertNotNil(pending.value)
        XCTAssertEqual(try own.summaries().items.count, 1)
        SessionURLProtocol.handler = { _ in (200, Data(#"{"revoked":true}"#.utf8)) }
        let restarted = AppSession(preferences: preferences(), api: api(), keychain: record, storageRoot: root,
            deletionStorage: pending, credentialState: { _ in .revoked })
        await restarted.restoreSession()
        XCTAssertFalse(restarted.hasPendingDeletion)
        XCTAssertNil(pending.value)
        XCTAssertNil(record.value)
        XCTAssertTrue(try own.summaries().items.isEmpty)
        XCTAssertEqual(try other.summaries().items.count, 1)
    }

    func testOldDeletionRecordDoesNotClearAnotherAccountsSignIn() async {
        let oldAccount = stored()
        var otherAccount = stored()
        otherAccount.tokens = AuthenticationTokens(accessToken: "other-access", refreshToken: "other-refresh",
            expiresAt: Date().timeIntervalSince1970 + 899, sessionExpiresAt: Date().timeIntervalSince1970 + 86400)
        let record = MemoryRecord(otherAccount)
        let pending = MemoryRecord<PendingAccountDeletion>(PendingAccountDeletion(authentication: oldAccount, serverConfirmed: true))
        SessionURLProtocol.handler = { _ in (503, Data()) }
        let session = AppSession(preferences: preferences(), api: api(), keychain: record,
            deletionStorage: pending, credentialState: { _ in .authorized })
        await session.restoreSession()
        XCTAssertEqual(record.value?.appleUserID, otherAccount.appleUserID)
        XCTAssertEqual(session.authentication?.appleUserID, otherAccount.appleUserID)
        XCTAssertNil(pending.value)
        session.signOut()
    }

    func testConfirmedDeletionRetriesLocalCleanupWithoutAnotherRevoke() async {
        let record = MemoryRecord(stored())
        let pending = MemoryRecord<PendingAccountDeletion>(PendingAccountDeletion(authentication: record.value!, serverConfirmed: true))
        record.failClear = true
        SessionURLProtocol.handler = { _ in XCTFail("No network call after confirmed deletion"); return (500, Data()) }
        let session = AppSession(preferences: preferences(), api: api(), keychain: record,
            deletionStorage: pending, credentialState: { _ in .revoked })
        await session.restoreSession()
        XCTAssertTrue(session.hasPendingDeletion)
        XCTAssertEqual(pending.value?.serverConfirmed, true)
        record.failClear = false
        await session.resumeAccountDeletion()
        XCTAssertFalse(session.hasPendingDeletion)
        XCTAssertNil(pending.value)
    }
}

private final class MemoryRecord<Value: Codable>: SecureRecordStorage {
    var value: Value?
    var failClear = false
    init(_ value: Value?) { self.value = value }
    func load() throws -> Value? { value }
    func save(_ value: Value) throws { self.value = value }
    func clear() throws {
        if failClear { throw AuthenticationError.keychain }
        value = nil
    }
}

private final class SessionURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
