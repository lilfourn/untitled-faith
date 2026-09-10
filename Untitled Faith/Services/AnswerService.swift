import Foundation

protocol AnswerService {
    func answer(for messages: [ChatMessage]) async throws -> FaithAnswer
    func streamAnswer(for messages: [ChatMessage],
                      onUpdate: @escaping @MainActor (String) -> Void) async throws -> FaithAnswer
}

extension AnswerService {
    func streamAnswer(for messages: [ChatMessage],
                      onUpdate: @escaping @MainActor (String) -> Void) async throws -> FaithAnswer {
        let result = try await answer(for: messages)
        await onUpdate(result.text)
        return result
    }
}

struct UnconfiguredAnswerService: AnswerService {
    func answer(for messages: [ChatMessage]) async throws -> FaithAnswer {
        throw AnswerServiceError.notConnected
    }
}

enum AnswerServiceError: LocalizedError {
    case notConnected
    case invalidConfiguration
    case signInRequired
    case consentRequired
    case conversationTooLong
    case questionTooLong
    case rateLimited
    case unavailable
    case timedOut
    case invalidResponse
    case sourcesUnavailable
    case fundingRequired
    case dailyFreeLimit
    case monthlyFreeLimit
    case freePoolUnavailable
    case requestConflict

    var errorDescription: String? {
        switch self {
        case .notConnected: "Answers aren’t connected yet. No answer has been generated."
        case .invalidConfiguration: "The answer service isn’t configured correctly. Please try again later."
        case .signInRequired: "Your answer session is unavailable or has expired. Please sign in again."
        case .consentRequired: "AI answers are off. Turn them on in Settings to send a question."
        case .conversationTooLong: "This conversation has reached the size limit. Start a new conversation to continue."
        case .questionTooLong: "Please shorten your question to 8,000 characters or fewer."
        case .rateLimited: "Too many answer requests right now. Please wait a minute before trying again."
        case .unavailable: "We couldn’t get an answer right now. Please try again later."
        case .timedOut: "The answer took too long. Please try again."
        case .sourcesUnavailable: "We couldn’t verify the sources for this answer. Your question is saved; please retry."
        case .invalidResponse: "We couldn’t read the answer. Please try again."
        case .dailyFreeLimit: "You’ve reached today’s free answer limit. Your monthly allowance may still have answers left. Check Settings for the reset time."
        case .monthlyFreeLimit: "You’ve used this month’s free answers. Check Settings for the reset date or available funding."
        case .freePoolUnavailable: "Free answers are temporarily unavailable because the shared free budget can’t cover this request. Your personal allowance may still have answers left."
        case .fundingRequired: "No free answers are available right now, and your funding balance can’t cover this question. Check your allowance in Settings."
        case .requestConflict: "This question is already being processed or has already been counted. Please check your conversation before sending again."
        }
    }
}
