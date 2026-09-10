import Foundation

struct ProxyAnswerService: AnswerService {
    static let consentVersion = "2026-09-09-openrouter-google"
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
            switch response.statusCode {
            case 200: break
            case 401: throw AnswerServiceError.signInRequired
            case 402: throw AnswerServiceError.fundingRequired
            case 409: throw AnswerServiceError.requestConflict
            case 403: throw AnswerServiceError.consentRequired
            case 413: throw AnswerServiceError.conversationTooLong
            case 429: throw AnswerServiceError.rateLimited
            case 504: throw AnswerServiceError.timedOut
            default: throw AnswerServiceError.unavailable
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
