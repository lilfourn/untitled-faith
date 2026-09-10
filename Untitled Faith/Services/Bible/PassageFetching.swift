import Foundation

/// Exact passages from a licensed translation service, keyed by the references they match.
struct QuotedPassages: Sendable {
    let translation: String
    let passages: [BibleReference: String]
}

protocol PassageFetching {
    func passages(for references: [BibleReference]) async throws -> QuotedPassages
}

enum PassageServiceError: Error {
    case unavailable
}
