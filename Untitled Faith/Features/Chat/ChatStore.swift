import Foundation
import Observation

@MainActor
@Observable
final class ChatStore {
    private(set) var conversation = Conversation()
    private(set) var history: [ConversationSummary] = []
    private(set) var isSending = false
    enum LoadingPhase: String { case thinking = "Thinking…", writing = "Writing…" }
    private(set) var loadingPhase: LoadingPhase?
    private(set) var revealingMessageID: UUID?
    private(set) var revealProgress: Double?
    var draft = ""
    var errorMessage: String?
    var storageError: String?
    private let service: any AnswerService
    private let storage: LocalConversationStorage?
    private let quoter: ScriptureQuoter?

    init(service: any AnswerService, storage: LocalConversationStorage? = nil, quoter: ScriptureQuoter? = nil) {
        self.service = service
        self.storage = storage
        self.quoter = quoter
        refreshHistory()
    }

    var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send(animate: Bool = true) async {
        guard canSend else { return }
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = conversation
        next.messages.append(.question(id: UUID(), text: question))
        next.updatedAt = Date()
        do {
            _ = try ProxyAnswerService.context(from: next.messages)
            try storage?.save(next)
        } catch {
            errorMessage = error is AnswerServiceError ? error.localizedDescription : "We couldn’t save this conversation on your phone. Your question hasn’t been sent."
            return
        }
        conversation = next
        draft = ""
        errorMessage = nil
        storageError = nil
        refreshHistory()
        isSending = true
        let answerID = UUID()
        loadingPhase = .thinking
        var receivedAnswer = false
        defer {
            isSending = false
            loadingPhase = nil
            revealingMessageID = nil
            revealProgress = nil
            refreshHistory()
        }

        do {
            // Provider deltas only update the status. Display and save a response after final validation.
            let messages = conversation.messages
            let answer = try await service.streamAnswer(for: messages) { [weak self] text in
                guard let self, !text.isEmpty else { return }
                self.loadingPhase = .writing
            }
            try Task.checkCancellation()
            receivedAnswer = true
            loadingPhase = nil
            if animate {
                revealingMessageID = answerID
                revealProgress = 0
            }
            setAnswer(id: answerID, answer: answer)
            saveCurrent()
            // Verse cards resolve while the text reveals, so quoting never delays the answer.
            async let citedAnswer = withCitations(answer)
            if animate { try await reveal(answer) }
            if let citedAnswer = await citedAnswer {
                setAnswer(id: answerID, answer: citedAnswer)
                saveCurrent()
            }
        } catch is CancellationError {
            if !receivedAnswer { errorMessage = "Response stopped." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func newConversation() {
        guard !isSending else { return }
        conversation = Conversation()
        draft = ""
        errorMessage = nil
    }

    func openConversation(_ id: UUID) {
        guard !isSending, let storage else { return }
        do {
            conversation = try storage.load(id)
            draft = ""
            errorMessage = nil
        } catch { storageError = "We couldn’t open this saved conversation. It hasn’t been deleted." }
    }

    func deleteConversation(_ id: UUID) {
        guard !isSending, let storage else { return }
        do {
            try storage.delete(id)
            if conversation.id == id { newConversation() }
            refreshHistory()
        } catch { storageError = "We couldn’t delete this conversation. Please try again." }
    }

    private func reveal(_ answer: FaithAnswer) async throws {
        let duration = min(4.0, max(0.5, Double(answer.text.count) / 450))
        let clock = ContinuousClock()
        let started = clock.now
        while true {
            try Task.checkCancellation()
            let elapsed = started.duration(to: clock.now).components
            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            revealProgress = min(1, seconds / duration)
            if revealProgress == 1 { break }
            try await Task.sleep(for: .milliseconds(33))
        }
    }

    /// Adds verse cards for references the answer mentions. Nil when nothing was resolved.
    private func withCitations(_ answer: FaithAnswer) async -> FaithAnswer? {
        guard let quoter, answer.scripture.isEmpty else { return nil }
        let references = Array(ScriptureReferenceDetector.references(in: answer.text).prefix(8))
        guard !references.isEmpty else { return nil }
        let citations = await quoter.citations(for: references)
        guard !citations.isEmpty else { return nil }
        return FaithAnswer(text: answer.text, scripture: citations, commentary: answer.commentary,
                           isComplete: answer.isComplete, sources: answer.sources, quotes: answer.quotes)
    }

    private func setAnswer(id: UUID, answer: FaithAnswer) {
        if let index = conversation.messages.firstIndex(where: { $0.id == id }) {
            conversation.messages[index] = .answer(id: id, answer: answer)
        } else {
            conversation.messages.append(.answer(id: id, answer: answer))
        }
    }

    private func saveCurrent() {
        guard !conversation.messages.isEmpty else { return }
        conversation.updatedAt = Date()
        do {
            try storage?.save(conversation)
            storageError = nil
        } catch { storageError = "We couldn’t save the latest messages on your phone. Keep this conversation open and try again." }
    }

    private func refreshHistory() {
        guard let storage else { return }
        do {
            let result = try storage.summaries()
            history = result.items
            if result.unreadableCount > 0 { storageError = "Some saved conversations couldn’t be read. They haven’t been deleted." }
        } catch { storageError = "We couldn’t load your saved conversations. Please try again." }
    }
}
