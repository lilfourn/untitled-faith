import Foundation

struct AppleExchangeRequest: Encodable {
    let identityToken: String
    let authorizationCode: String
    let nonce: String
    var firstName: String? = nil
}

struct AuthenticationTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
    let sessionExpiresAt: TimeInterval

    var needsRefresh: Bool { expiresAt <= Date().timeIntervalSince1970 + 60 }
    var isExpired: Bool { sessionExpiresAt <= Date().timeIntervalSince1970 }
}

struct StoredAuthentication: Codable {
    let appleUserID: String
    let apiBaseURL: URL
    var tokens: AuthenticationTokens
}

struct AuthenticationAPI {
    let baseURL: URL
    var session: URLSession = ProxyAnswerService.makeSession()

    static func configured() -> AuthenticationAPI? {
        var base = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
        var answer = Bundle.main.object(forInfoDictionaryKey: "AnswerProxyURL") as? String
        #if DEBUG
        base = ProcessInfo.processInfo.environment["FAITH_API_BASE_URL"] ?? base
        answer = ProcessInfo.processInfo.environment["FAITH_PROXY_URL"] ?? answer
        #endif
        if base?.isEmpty != false, let answer, answer.hasSuffix("/v1/answers") {
            base = String(answer.dropLast("/v1/answers".count))
        }
        guard let base, let url = URL(string: base), isSecureBaseURL(url) else { return nil }
        return AuthenticationAPI(baseURL: url)
    }

    static func isSecureBaseURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false &&
        url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }

    func exchange(_ credentials: AppleExchangeRequest) async throws -> AuthenticationTokens {
        try await tokens(path: "v1/auth/apple", body: credentials)
    }

    func refresh(_ token: String) async throws -> AuthenticationTokens {
        try await tokens(path: "v1/auth/refresh", body: RefreshRequest(refreshToken: token))
    }

    func revoke(_ token: String) async throws {
        let data = try await post(path: "v1/auth/revoke", body: RefreshRequest(refreshToken: token))
        guard let result = try? JSONDecoder().decode(RevocationResponse.self, from: data), result.revoked else {
            throw AuthenticationError.unavailable
        }
    }

    private func tokens<Body: Encodable>(path: String, body: Body) async throws -> AuthenticationTokens {
        let data = try await post(path: path, body: body)
        let now = Date().timeIntervalSince1970
        guard let tokens = try? JSONDecoder().decode(AuthenticationTokens.self, from: data),
              !tokens.accessToken.isEmpty, tokens.accessToken.count <= 4096,
              !tokens.refreshToken.isEmpty, tokens.refreshToken.count <= 16384,
              tokens.expiresAt > now, tokens.expiresAt <= now + 905,
              tokens.sessionExpiresAt >= tokens.expiresAt,
              tokens.sessionExpiresAt <= now + 30 * 86400 + 5 else {
            throw AuthenticationError.unavailable
        }
        return tokens
    }

    private func post<Body: Encodable>(path: String, body: Body) async throws -> Data {
        guard Self.isSecureBaseURL(baseURL) else { throw AuthenticationError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, data.count <= 32 * 1024 else {
                throw AuthenticationError.unavailable
            }
            switch response.statusCode {
            case 200: return data
            case 401: throw AuthenticationError.invalidCredential
            case 409: throw AuthenticationError.unsettledFunding
            case 429: throw AuthenticationError.rateLimited
            case 503: throw AuthenticationError.notConfigured
            default: throw AuthenticationError.unavailable
            }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw AuthenticationError.unavailable
        }
    }
}

private struct RefreshRequest: Encodable { let refreshToken: String }
private struct RevocationResponse: Decodable { let revoked: Bool }

enum AuthenticationError: LocalizedError {
    case invalidCredential, unavailable, notConfigured, rateLimited, keychain, unsettledFunding

    var errorDescription: String? {
        switch self {
        case .invalidCredential: "Your sign-in has expired or could not be verified. Please sign in again."
        case .unavailable: "We couldn’t reach the sign-in service. Please try again."
        case .notConfigured: "Sign-in setup is not complete yet. Please try again later."
        case .rateLimited: "Too many sign-in attempts. Please wait a minute and try again."
        case .keychain: "We couldn’t securely save your sign-in on this device. Please try again."
        case .unsettledFunding: "Your account still has funding or unsettled usage. Please let pending requests finish, or contact untitledfaith@gmail.com to resolve remaining funding before deletion."
        }
    }
}
