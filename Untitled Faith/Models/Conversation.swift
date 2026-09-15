import Foundation

struct Conversation: Identifiable, Codable {
    var id = UUID()
    var updatedAt = Date()
    var messages: [ChatMessage] = []

    var title: String {
        guard case .question(_, let text, let scripture)? = messages.first else { return "New conversation" }
        if text.isEmpty { return scripture?.first?.reference ?? "New conversation" }
        return String(text.prefix(70))
    }
}

enum ChatMessage: Identifiable, Codable {
    case question(id: UUID, text: String, scripture: [ScriptureCitation]? = nil)
    case answer(id: UUID, answer: FaithAnswer)

    var text: String {
        switch self {
        case .question(_, let text, _): text
        case .answer(_, let answer): answer.text
        }
    }

    var id: UUID {
        switch self {
        case .question(let id, _, _), .answer(let id, _): id
        }
    }

    /// Keep the full selected text in every request, including retries and history follow-ups.
    var promptText: String {
        guard case .question(_, let text, let scripture) = self, let scripture, !scripture.isEmpty else { return text }
        let passages = scripture.map { "\($0.reference) (\($0.translation))\n\($0.passage)" }.joined(separator: "\n\n")
        return [text, "Attached Scripture:\n\(passages)"].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

struct FaithAnswer: Codable {
    let text: String
    let scripture: [ScriptureCitation]
    let commentary: [CommentaryCitation]
    var isComplete = true
    var sources: [AnswerSource]? = nil
    var quotes: [AnswerQuote]? = nil
}

struct ScriptureCitation: Identifiable, Codable, Sendable {
    let id: UUID
    let reference: String
    let translation: String
    let passage: String
}

struct CommentaryCitation: Identifiable, Codable {
    let id: UUID
    let author: String
    let organization: String?
    let title: String
    let excerpt: String
    let sourceURL: URL
}
