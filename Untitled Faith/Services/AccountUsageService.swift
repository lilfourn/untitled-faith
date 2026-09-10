import Foundation

struct AccountUsage: Decodable {
    let month: String
    let resetsAt: String
    let currency: String
    let appAccountToken: UUID
    let remainingPercent: Int
    let free: FreeAllowance
    let funding: Funding
    let usage: Usage

    struct FreeAllowance: Decodable {
        let monthlyLimit: Int
        let usedThisMonth: Int
        let remainingThisMonth: Int
    }
    struct Funding: Decodable {
        let balanceMicros: Int64
        let reservedMicros: Int64
        let availableMicros: Int64
    }
    struct Usage: Decodable {
        let totalRequests: Int
        let pendingRequests: Int
        let promptTokens: Int
        let completionTokens: Int
        let costMicros: Int64
    }
}

struct AccountUsageService {
    let baseURL: URL
    var session: URLSession = ProxyAnswerService.makeSession()

    func load(accessToken: String) async throws -> AccountUsage {
        guard AuthenticationAPI.isSecureBaseURL(baseURL) else { throw AnswerServiceError.invalidConfiguration }
        guard !accessToken.isEmpty else { throw AnswerServiceError.signInRequired }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/me/usage"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw AnswerServiceError.unavailable }
            if http.statusCode == 401 { throw AnswerServiceError.signInRequired }
            guard http.statusCode == 200, data.count <= 32 * 1024,
                  let result = try? JSONDecoder().decode(AccountUsage.self, from: data), result.currency == "USD",
                  result.funding.availableMicros >= 0, result.funding.reservedMicros >= 0,
                  (0...100).contains(result.remainingPercent) else {
                throw AnswerServiceError.unavailable
            }
            return result
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw AnswerServiceError.unavailable
        }
    }
}
