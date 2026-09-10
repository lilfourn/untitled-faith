import Foundation

struct ProxyAnswerService: AnswerService {
    static let consentVersion = "2026-09-09-openrouter-fallbacks"
    let endpoint: URL
    let accessToken: @MainActor () async throws -> String
    let hasConsent: @MainActor () -> Bool
    var session: URLSession = makeSession()

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 55
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    }

    func answer(for messages: [ChatMessage]) async throws -> FaithAnswer {
        let request = try await makeRequest(messages, accept: "application/json")
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw AnswerServiceError.invalidResponse }
            guard response.statusCode == 200 else {
                throw Self.failure(status: response.statusCode, data: data)
            }
            guard data.count <= 128 * 1024,
                  let result = try? JSONDecoder().decode(AnswerResponse.self, from: data) else {
                throw AnswerServiceError.invalidResponse
            }
            return try result.answer.validatedAnswer()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? AnswerServiceError.timedOut : AnswerServiceError.unavailable
        }
    }

    func requestStatus(for messageID: UUID) async throws -> AnswerAttemptStatus {
        guard AuthenticationAPI.isSecureBaseURL(endpoint) else { throw AnswerServiceError.invalidConfiguration }
        let token = try await accessToken()
        guard !token.isEmpty else { throw AnswerServiceError.signInRequired }
        var request = URLRequest(url: endpoint.appendingPathComponent("status").appendingPathComponent(messageID.uuidString))
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AnswerServiceError.unavailable }
        guard http.statusCode == 200 else { throw Self.failure(status: http.statusCode, data: data) }
        struct Status: Decodable { let status: AnswerAttemptStatus }
        guard data.count <= 4096, let status = try? JSONDecoder().decode(Status.self, from: data) else {
            throw AnswerServiceError.invalidResponse
        }
        return status.status
    }

    static func failure(status: Int, data: Data? = nil) -> AnswerServiceError {
        let code = data.flatMap { data in
            data.count <= 16 * 1024 ? (try? JSONDecoder().decode(FailureResponse.self, from: data))?.error.code : nil
        }
        if code == "invalid_answer_format" { return .invalidResponse }
        switch status {
        case 401: return .signInRequired
        case 402:
            switch code {
            case "monthly_free_limit": return .monthlyFreeLimit
            case "free_pool_exhausted": return .freePoolUnavailable
            default: return .fundingRequired
            }
        case 409: return .requestConflict
        case 403: return .consentRequired
        case 413: return .conversationTooLong
        case 429: return .rateLimited
        case 504: return .timedOut
        default: return code == "sources_unavailable" ? .sourcesUnavailable : .unavailable
        }
    }

    func makeRequest(_ messages: [ChatMessage], accept: String) async throws -> URLRequest {
        guard endpoint.scheme?.lowercased() == "https", endpoint.host != nil,
              endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil else {
            throw AnswerServiceError.invalidConfiguration
        }
        guard await hasConsent() else { throw AnswerServiceError.consentRequired }
        let token = try await accessToken()
        guard !token.isEmpty else { throw AnswerServiceError.signInRequired }
        let context = try Self.context(from: messages)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(messages.last?.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(AnswerRequest(messages: context, consentVersion: Self.consentVersion))
        guard let body = request.httpBody, body.count <= 1024 * 1024 else { throw AnswerServiceError.conversationTooLong }
        try Task.checkCancellation()
        return request
    }

    // Send every displayed message in order. Never silently discard older context.
    static func context(from messages: [ChatMessage]) throws -> [WireMessage] {
        guard case .question(_, let latest)? = messages.last else { throw AnswerServiceError.invalidResponse }
        guard latest.utf16.count <= 8000 else { throw AnswerServiceError.questionTooLong }
        guard messages.count <= 1000 else { throw AnswerServiceError.conversationTooLong }
        let context = messages.map { message -> WireMessage in
            switch message {
            case .question(_, let text): return WireMessage(role: "user", content: text)
            case .answer(_, let answer): return WireMessage(role: "assistant", content: answer.text)
            }
        }
        guard context.allSatisfy({ $0.content.utf16.count <= 8000 }),
              context.reduce(0, { $0 + $1.content.utf16.count }) <= 200_000 else {
            throw AnswerServiceError.conversationTooLong
        }
        return context
    }

}

struct WireMessage: Encodable {
    let role: String
    let content: String
}

private struct AnswerRequest: Encodable {
    let messages: [WireMessage]
    let consentVersion: String
}

private struct AnswerResponse: Decodable {
    let answer: AnswerPayload

}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct FailureResponse: Decodable {
    let error: Failure
    struct Failure: Decodable { let code: String }
}
