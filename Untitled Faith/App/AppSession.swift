import AuthenticationServices
import Observation

@MainActor
@Observable
final class AppSession {
    private(set) var isPreview = false
    private(set) var isSigningIn = false
    private(set) var isRestoring = false
    private(set) var isDeletingAccount = false
    private(set) var authentication: StoredAuthentication?
    var signInError: String?
    var aiSharingAllowed: Bool {
        didSet { preferences.set(aiSharingAllowed, forKey: "aiAnswersEnabled") }
    }
    let accountUsage: AccountUsageStore
    private let preferences: UserDefaults
    private let usageService: AccountUsageService?
    private let keychain = AuthenticationKeychain()
    private var attempt: AppleSignInAttempt?
    private var generation = UUID()
    private var didRestore = false
    @ObservationIgnored private var refreshTask: Task<AuthenticationTokens, Error>?

    var isSignedIn: Bool { authentication != nil }
    var canSignIn: Bool { AuthenticationAPI.configured() != nil && !isSigningIn && !isRestoring }

    func refreshUsage(force: Bool = false) {
        guard isSignedIn, !isPreview, !isDeletingAccount else { return }
        accountUsage.refresh(force: force) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.loadUsage()
        }
    }

    private func loadUsage() async throws -> AccountUsage {
        guard let usageService else { throw AnswerServiceError.notConnected }
        let token = try await validAccessToken()
        return try await usageService.load(accessToken: token)
    }

    func makeConversationStorage() -> LocalConversationStorage {
        LocalConversationStorage(namespace: localStorageNamespace)
    }

    func makeProfilePhotoStorage() -> LocalProfilePhotoStorage {
        LocalProfilePhotoStorage(namespace: localStorageNamespace)
    }

    private var localStorageNamespace: String {
        let identity = authentication?.appleUserID ?? "development-preview"
        let backend = authentication?.apiBaseURL.absoluteString ?? AuthenticationAPI.configured()?.baseURL.absoluteString ?? "preview"
        return backend + "|" + identity
    }

    func makeAnswerService() -> any AnswerService {
        var endpoint = Bundle.main.object(forInfoDictionaryKey: "AnswerProxyURL") as? String
        #if DEBUG
        endpoint = ProcessInfo.processInfo.environment["FAITH_PROXY_URL"] ?? endpoint
        #endif
        let url = endpoint.flatMap { $0.isEmpty ? nil : URL(string: $0) } ?? AuthenticationAPI.configured()?.baseURL.appendingPathComponent("v1/answers")
        guard let url else {
            return UnconfiguredAnswerService()
        }
        return ProxyAnswerService(endpoint: url, accessToken: { [weak self] in
            guard let self else { throw AnswerServiceError.signInRequired }
            return try await self.proxyAccessToken()
        }, hasConsent: { [weak self] in self?.aiSharingAllowed == true })
    }

    /// Verse cards: ESV through the backend when configured, cached on device within Crossway's limits,
    /// with the bundled public-domain translation as the offline fallback.
    func makeScriptureQuoter() -> ScriptureQuoter {
        let service = AuthenticationAPI.configured().map { api in
            ESVPassageClient(endpoint: api.baseURL.appendingPathComponent("v1/passages"), accessToken: { [weak self] in
                guard let self else { throw AnswerServiceError.signInRequired }
                return try await self.proxyAccessToken()
            })
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ScriptureQuoter(service: service, cache: PassageCache(directory: support.appendingPathComponent("Passages", isDirectory: true)),
                               fallback: BibleStore.bundled)
    }

    private func proxyAccessToken() async throws -> String {
        #if DEBUG
        if isPreview, let token = ProcessInfo.processInfo.environment["FAITH_PROXY_SESSION_TOKEN"], !token.isEmpty {
            return token
        }
        #endif
        return try await validAccessToken()
    }

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        accountUsage = AccountUsageStore(preferences: preferences)
        usageService = AuthenticationAPI.configured().map { AccountUsageService(baseURL: $0.baseURL) }
        aiSharingAllowed = preferences.object(forKey: "aiAnswersEnabled") as? Bool ?? true
        #if DEBUG
        isPreview = ProcessInfo.processInfo.arguments.contains("--preview-chat")
        #endif
    }

    func prepareAppleAuthorization(_ request: ASAuthorizationAppleIDRequest) {
        signInError = nil
        do {
            let attempt = try AppleSignInAttempt()
            self.attempt = attempt
            attempt.configure(request)
            isSigningIn = true
        } catch {
            attempt = nil
            signInError = error.localizedDescription
        }
    }

    func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            let currentAttempt = attempt
            attempt = nil
            let currentGeneration = generation
            Task {
                defer { if generation == currentGeneration { isSigningIn = false } }
                do {
                    guard let currentAttempt else { throw AuthenticationError.invalidCredential }
                    guard let api = AuthenticationAPI.configured() else { throw AuthenticationError.notConfigured }
                    let credentials = try currentAttempt.credentials(from: authorization)
                    let tokens = try await api.exchange(credentials.request)
                    guard generation == currentGeneration else { return }
                    let stored = StoredAuthentication(appleUserID: credentials.userID, apiBaseURL: api.baseURL, tokens: tokens)
                    try keychain.save(stored)
                    authentication = stored
                    isPreview = false
                    accountUsage.activate(namespace: localStorageNamespace)
                    refreshUsage(force: true)
                } catch {
                    if generation == currentGeneration { signInError = error.localizedDescription }
                }
            }
        case .failure(let error):
            attempt = nil
            isSigningIn = false
            guard (error as? ASAuthorizationError)?.code != .canceled else { return }
            signInError = "We couldn’t complete Apple sign-in. Please try again later."
        }
    }

    func restoreSession() async {
        guard !didRestore else { return }
        didRestore = true
        guard !isPreview, let api = AuthenticationAPI.configured() else { return }
        isRestoring = true
        defer { isRestoring = false }
        let currentGeneration = generation
        do {
            guard let stored = try keychain.load() else { return }
            guard stored.apiBaseURL == api.baseURL, !stored.tokens.isExpired else {
                try keychain.clear()
                return
            }
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: stored.appleUserID)
            guard generation == currentGeneration else { return }
            guard state == .authorized else {
                try keychain.clear()
                return
            }
            authentication = stored
            accountUsage.activate(namespace: localStorageNamespace)
            _ = try await validAccessToken()
            refreshUsage(force: true)
        } catch {
            guard generation == currentGeneration else { return }
            authentication = nil
            accountUsage.clear()
            signInError = error.localizedDescription
        }
    }

    func checkAppleCredential() async {
        guard let stored = authentication else { return }
        let currentGeneration = generation
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: stored.appleUserID)
            guard generation == currentGeneration else { return }
            if state != .authorized { signOut() }
        } catch {
            // A transient credential-state failure must not erase a restorable session.
        }
    }

    private func validAccessToken() async throws -> String {
        guard var stored = authentication else { throw AnswerServiceError.signInRequired }
        guard !stored.tokens.isExpired else {
            signOut()
            throw AnswerServiceError.signInRequired
        }
        if !stored.tokens.needsRefresh { return stored.tokens.accessToken }
        guard let api = AuthenticationAPI.configured(), api.baseURL == stored.apiBaseURL else {
            throw AuthenticationError.notConfigured
        }
        let currentGeneration = generation
        let task: Task<AuthenticationTokens, Error>
        if let refreshTask { task = refreshTask }
        else {
            task = Task { try await api.refresh(stored.tokens.refreshToken) }
            refreshTask = task
        }
        defer { if generation == currentGeneration { refreshTask = nil } }
        do {
            stored.tokens = try await task.value
            guard generation == currentGeneration else { throw CancellationError() }
            try keychain.save(stored)
            authentication = stored
            return stored.tokens.accessToken
        } catch AuthenticationError.invalidCredential {
            if generation == currentGeneration { signOut() }
            throw AnswerServiceError.signInRequired
        }
    }

    func signOut() {
        generation = UUID()
        accountUsage.clear()
        refreshTask?.cancel()
        refreshTask = nil
        attempt = nil
        isSigningIn = false
        authentication = nil
        isPreview = false
        do { try keychain.clear() }
        catch { signInError = error.localizedDescription }
    }

    func deleteAccount() async {
        guard let stored = authentication, let api = AuthenticationAPI.configured(),
              stored.apiBaseURL == api.baseURL, !isDeletingAccount else { return }
        isDeletingAccount = true
        let currentGeneration = generation
        defer { isDeletingAccount = false }
        do {
            try await api.revoke(stored.tokens.refreshToken)
            guard generation == currentGeneration else { return }
            do { try makeConversationStorage().deleteAll() }
            catch { signInError = "Your account was deleted, but saved conversations couldn’t be removed from this device. Removing the app will clear its local data." }
            do { try makeProfilePhotoStorage().delete() }
            catch { signInError = "Your account was deleted, but some saved data couldn’t be removed from this device. Removing the app will clear its local data." }
            accountUsage.clear(removeCached: true)
            signOut()
        } catch {
            if generation == currentGeneration { signInError = error.localizedDescription }
        }
    }

    func endPreview() {
        isPreview = false
    }
}
