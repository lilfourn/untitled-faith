import Foundation

/// Fetches ESV passages through the app's backend, which holds the Crossway API key.
struct ESVPassageClient: PassageFetching {
    let endpoint: URL
    let accessToken: @MainActor () async throws -> String
    var session: URLSession = ProxyAnswerService.makeSession()

    func passages(for references: [BibleReference]) async throws -> QuotedPassages {
        guard !references.isEmpty else { return QuotedPassages(translation: "", passages: [:]) }
        guard endpoint.scheme?.lowercased() == "https", var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PassageServiceError.unavailable
        }
        let query = references.map { $0.description.replacingOccurrences(of: "–", with: "-") }.joined(separator: ";")
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { throw PassageServiceError.unavailable }
        let token = try await accessToken()
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 256 * 1024,
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw PassageServiceError.unavailable
        }
        var passages: [BibleReference: String] = [:]
        for passage in payload.passages {
            guard let reference = BibleReference.parse(passage.reference), !passage.text.isEmpty else { continue }
            passages[reference] = passage.text
        }
        return QuotedPassages(translation: payload.translation, passages: passages)
    }

    private struct Payload: Decodable {
        struct Passage: Decodable {
            let reference: String
            let text: String
        }
        let translation: String
        let passages: [Passage]
    }
}
