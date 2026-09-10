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
    private let keychain: any SecureRecordStorage<StoredAuthentication>
    private let deletionStorage: any SecureRecordStorage<PendingAccountDeletion>
    private let api: AuthenticationAPI?
    private let storageRoot: URL
    private let credentialState: (String) async throws -> ASAuthorizationAppleIDProvider.CredentialState
    private(set) var canRetryRestoration = false
    private(set) var hasPendingDeletion = false
    private var attempt: AppleSignInAttempt?
    private var generation = UUID()
    private var didRestore = false
    @ObservationIgnored private var refreshTask: Task<AuthenticationTokens, Error>?

    var isSignedIn: Bool { authentication != nil }
    var canSignIn: Bool { api != nil && !isSigningIn && !isRestoring && !hasPendingDeletion }

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
        LocalConversationStorage(namespace: localStorageNamespace, root: storageRoot)
    }

    func makeProfilePhotoStorage() -> LocalProfilePhotoStorage {
        LocalProfilePhotoStorage(namespace: localStorageNamespace, root: storageRoot)
    }

    private var localStorageNamespace: String {
        let identity = authentication?.appleUserID ?? "development-preview"
        let backend = authentication?.apiBaseURL.absoluteString ?? api?.baseURL.absoluteString ?? "preview"
        return backend + "|" + identity
    }

    func makeAnswerService() -> any AnswerService {
        var endpoint = Bundle.main.object(forInfoDictionaryKey: "AnswerProxyURL") as? String
        #if DEBUG
        endpoint = ProcessInfo.processInfo.environment["FAITH_PROXY_URL"] ?? endpoint
        #endif
        let url = endpoint.flatMap { $0.isEmpty ? nil : URL(string: $0) } ?? api?.baseURL.appendingPathComponent("v1/answers")
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
        let service = api.map { api in
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

    init(preferences: UserDefaults = .standard, api: AuthenticationAPI? = .configured(),
         keychain: any SecureRecordStorage<StoredAuthentication> = AuthenticationKeychain(),
         storageRoot: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
         deletionStorage: any SecureRecordStorage<PendingAccountDeletion> = KeychainRecord<PendingAccountDeletion>(service: "com.lukefournier.UntitledFaith.pending-deletion"),
         credentialState: @escaping (String) async throws -> ASAuthorizationAppleIDProvider.CredentialState = {
             try await ASAuthorizationAppleIDProvider().credentialState(forUserID: $0)
         }) {
        self.preferences = preferences
        self.api = api
        self.storageRoot = storageRoot
        self.keychain = keychain
        self.deletionStorage = deletionStorage
        self.credentialState = credentialState
        accountUsage = AccountUsageStore(preferences: preferences)
        usageService = api.map { AccountUsageService(baseURL: $0.baseURL, session: $0.session) }
        aiSharingAllowed = preferences.object(forKey: "aiAnswersEnabled") as? Bool ?? true
        #if DEBUG
        isPreview = ProcessInfo.processInfo.arguments.contains("--preview-chat")
        #endif
        if !isPreview {
            do { hasPendingDeletion = try deletionStorage.load() != nil }
            catch { hasPendingDeletion = true; canRetryRestoration = true }
        }
    }

    func prepareAppleAuthorization(_ request: ASAuthorizationAppleIDRequest) {
        guard canSignIn else { return }
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
                    guard let api else { throw AuthenticationError.notConfigured }
                    let credentials = try currentAttempt.credentials(from: authorization)
                    let tokens = try await api.exchange(credentials.request)
                    guard generation == currentGeneration else { return }
                    let stored = StoredAuthentication(appleUserID: credentials.userID, apiBaseURL: api.baseURL, tokens: tokens)
                    try keychain.save(stored)
                    authentication = stored
                    canRetryRestoration = false
                    didRestore = true
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

    func restoreSession(retry: Bool = false) async {
        guard !isRestoring, !isSigningIn, !isDeletingAccount,
              !didRestore || (retry && canRetryRestoration) else { return }
        guard !isPreview, let api else { return }
        didRestore = true
        isRestoring = true
        canRetryRestoration = false
        signInError = nil
        defer { isRestoring = false }
        var currentGeneration = generation
        do {
            hasPendingDeletion = try deletionStorage.load() != nil
            if hasPendingDeletion {
                await resumeAccountDeletion()
                guard !hasPendingDeletion else { return }
                currentGeneration = generation
                didRestore = true
            }
            guard let stored = try keychain.load() else { return }
            guard stored.apiBaseURL == api.baseURL, !stored.tokens.isExpired else {
                try keychain.clear()
                return
            }
            let state = try await credentialState(stored.appleUserID)
            guard generation == currentGeneration else { return }
            guard state == .authorized else {
                try keychain.clear()
                authentication = nil
                accountUsage.clear()
                return
            }
            authentication = stored
            accountUsage.activate(namespace: localStorageNamespace)
            _ = try await validAccessToken()
            refreshUsage(force: true)
        } catch {
            guard generation == currentGeneration else { return }
            // Keep the Keychain record and any already-validated local account on transient failure.
            canRetryRestoration = true
            signInError = error.localizedDescription
        }
    }

    func becameActive() async {
        if hasPendingDeletion {
            await resumeAccountDeletion()
            guard !hasPendingDeletion else { return }
        }
        await restoreSession(retry: true)
        await checkAppleCredential()
        refreshUsage(force: true)
    }

    func handleCredentialRevocation() {
        // Apple's notification can arrive before our deletion response. Preserve that workflow.
        if !hasPendingDeletion { signOut() }
    }

    func checkAppleCredential() async {
        guard let stored = authentication else { return }
        let currentGeneration = generation
        do {
            let state = try await credentialState(stored.appleUserID)
            guard generation == currentGeneration else { return }
            if state != .authorized { signOut() }
        } catch {
            // A transient credential-state failure must not erase a restorable session.
        }
    }

    private func validAccessToken() async throws -> String {
        guard !hasPendingDeletion, var stored = authentication else { throw AnswerServiceError.signInRequired }
        guard !stored.tokens.isExpired else {
            signOut()
            throw AnswerServiceError.signInRequired
        }
        if !stored.tokens.needsRefresh { return stored.tokens.accessToken }
        guard let api, api.baseURL == stored.apiBaseURL else {
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
        resetSessionState()
        do { try keychain.clear() }
        catch { signInError = error.localizedDescription }
    }

    private func resetSessionState() {
        generation = UUID()
        didRestore = true
        canRetryRestoration = false
        accountUsage.clear()
        refreshTask?.cancel()
        refreshTask = nil
        attempt = nil
        isSigningIn = false
        authentication = nil
        isPreview = false
    }

    func deleteAccount() async {
        guard !isDeletingAccount else { return }
        do {
            if try deletionStorage.load() == nil {
                guard let stored = authentication, let api, stored.apiBaseURL == api.baseURL else { return }
                // Persist authorization before making any destructive network call.
                try deletionStorage.save(PendingAccountDeletion(authentication: stored))
            }
            hasPendingDeletion = true
            await resumeAccountDeletion()
        } catch { signInError = error.localizedDescription }
    }

    func resumeAccountDeletion() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            guard var pending = try deletionStorage.load() else {
                hasPendingDeletion = false
                return
            }
            hasPendingDeletion = true
            guard let api, pending.authentication.apiBaseURL == api.baseURL else { throw AuthenticationError.notConfigured }
            if !pending.serverConfirmed {
                try await api.revoke(pending.authentication.tokens.refreshToken)
                pending.serverConfirmed = true
                try deletionStorage.save(pending)
            }
            // All cleanup operations are repeatable and scoped to the original account.
            try LocalConversationStorage(namespace: pending.namespace, root: storageRoot).deleteAll()
            try LocalProfilePhotoStorage(namespace: pending.namespace, root: storageRoot).delete()
            AccountUsageStore.removeCache(namespace: pending.namespace, preferences: preferences)
            let current = try keychain.load()
            if current?.appleUserID == pending.authentication.appleUserID && current?.apiBaseURL == pending.authentication.apiBaseURL {
                try keychain.clear()
            }
            try deletionStorage.clear()
            hasPendingDeletion = false
            if authentication == nil || (authentication?.appleUserID == pending.authentication.appleUserID &&
                authentication?.apiBaseURL == pending.authentication.apiBaseURL) {
                resetSessionState()
                didRestore = false
            }
            signInError = nil
        } catch {
            signInError = "Account deletion is not finished. Retry to complete it. " + error.localizedDescription
        }
    }

    func makePaymentAPI() -> PaymentAPI? {
        guard let api, isSignedIn, !isPreview, !hasPendingDeletion else { return nil }
        let currentGeneration = generation
        return PaymentAPI(baseURL: api.baseURL, accessToken: { [weak self] in
            guard let self, self.generation == currentGeneration, !self.hasPendingDeletion else { throw CancellationError() }
            return try await self.validAccessToken()
        }, isCurrentSession: { [weak self] in
            self?.generation == currentGeneration && self?.isSignedIn == true && self?.hasPendingDeletion == false
        }, session: api.session)
    }

    func endPreview() {
        isPreview = false
    }
}
