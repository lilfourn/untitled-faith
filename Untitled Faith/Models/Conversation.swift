import Foundation

struct Conversation: Identifiable, Codable {
    var id = UUID()
    var updatedAt = Date()
    var messages: [ChatMessage] = []

    var title: String {
        guard case .question(_, let text)? = messages.first else { return "New conversation" }
        return String(text.prefix(70))
    }
}

enum ChatMessage: Identifiable, Codable {
    case question(id: UUID, text: String)
    case answer(id: UUID, answer: FaithAnswer)

    var text: String {
        switch self {
        case .question(_, let text): text
        case .answer(_, let answer): answer.text
        }
    }

    var id: UUID {
        switch self {
        case .question(let id, _), .answer(let id, _): id
        }
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

struct ScriptureCitation: Identifiable, Codable {
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
