import Foundation

struct AnswerSource: Codable, Identifiable {
    enum Kind: String, Codable { case scripture, commentary }
    let id: UUID
    let title: String
    let url: URL
    let kind: Kind

    static func canonicalURL(_ url: URL) -> URL? {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.replacingOccurrences(of: "www.", with: "", options: .anchored),
              ["biblegateway.com", "bible.com", "esv.org", "bibleproject.com", "gotquestions.org"].contains(host),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.fragment = nil
        return parts.url
    }
}

struct AnswerQuote: Codable, Identifiable {
    let id: UUID
    let text: String
    let attribution: String
    let sourceID: UUID
    let startIndex: Int
    let endIndex: Int
}

// Shared by JSON and streaming responses. The legacy citation arrays stay empty.
struct AnswerPayload: Decodable {
    let text: String
    let scripture: [String]
    let commentary: [String]
    let sources: [AnswerSource]?
    let quotes: [AnswerQuote]?

    func validatedAnswer() throws -> FaithAnswer {
        let sources = sources ?? []
        let quotes = quotes ?? []
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= 8000,
              scripture.isEmpty, commentary.isEmpty, sources.count <= 20, quotes.count <= 20,
              Set(sources.map(\.id)).count == sources.count,
              Set(quotes.map(\.id)).count == quotes.count,
              sources.allSatisfy({ AnswerSource.canonicalURL($0.url) != nil && $0.title.count <= 240 }) else {
            throw AnswerServiceError.invalidResponse
        }
        var previousEnd = 0
        for quote in quotes {
            guard quote.startIndex >= previousEnd, quote.endIndex > quote.startIndex, quote.endIndex <= text.utf16.count,
                  !quote.text.isEmpty, quote.text.utf16.count <= text.utf16.count, quote.attribution.count <= 200,
                  sources.contains(where: { $0.id == quote.sourceID }),
                  Range(NSRange(location: quote.startIndex, length: quote.endIndex - quote.startIndex), in: text) != nil else {
                throw AnswerServiceError.invalidResponse
            }
            previousEnd = quote.endIndex
        }
        return FaithAnswer(text: text, scripture: [], commentary: [], sources: sources, quotes: quotes)
    }
}
