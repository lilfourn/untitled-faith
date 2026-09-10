import XCTest
@testable import Untitled_Faith

@MainActor
final class ChatSessionTests: XCTestCase {
    private var root: URL!
    override func setUp() { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func testSubmissionClearsImmediatelyAndIgnoresStaleKeyboardUpdates() async throws {
        let service = RecordingAnswerService()
        let store = ChatStore(service: service)
        store.draft = "  Question  "
        let revision = store.draftRevision
        let task = try XCTUnwrap(store.startSend(animate: false))
        XCTAssertEqual(store.draft, "")
        XCTAssertTrue(store.isSending)
        XCTAssertEqual(store.conversation.messages.map(\.text), ["Question"])
        store.updateDraft("  Question  ", revision: revision)
        XCTAssertEqual(store.draft, "")
        store.updateDraft("Next question", revision: store.draftRevision)
        XCTAssertNil(store.startSend(animate: false))
        await task.value
        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(store.draft, "Next question")
    }

    func testRetryRestoresUnansweredQuestionWithoutDuplicatingItOrClearingNewDraft() async throws {
        let storage = LocalConversationStorage(namespace: "one", root: root)
        let service = RecordingAnswerService()
        service.failure = .unavailable
        let store = ChatStore(service: service, storage: storage)
        store.draft = "Question"
        await store.send(animate: false)
        XCTAssertTrue(store.canRetry)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.loadingPhase)
        let originalMessageID = try XCTUnwrap(store.conversation.messages.last?.id)
        let restored = ChatStore(service: service, storage: storage)
        restored.openConversation(store.conversation.id)
        XCTAssertTrue(restored.canRetry)
        restored.draft = "Next question"
        service.failure = nil
        let task = try XCTUnwrap(restored.startSend(animate: false, retrying: true))
        XCTAssertNil(restored.startSend(animate: false, retrying: true))
        await task.value
        XCTAssertEqual(restored.conversation.messages.map(\.text), ["Question", "A streamed answer"])
        XCTAssertEqual(restored.draft, "Next question")
        XCTAssertNotEqual(service.requests.last?.last?.id, originalMessageID)
        XCTAssertEqual(try storage.load(store.conversation.id).messages.count, 2)
        XCTAssertFalse(restored.canRetry)
        XCTAssertNil(restored.errorMessage)
    }

    func testRetryCheckDoesNotResubmitWhileOriginalRequestIsProcessing() async {
        let service = RecordingAnswerService()
        service.failure = .unavailable
        service.status = .reserved
        let store = ChatStore(service: service)
        store.draft = "Question"
        await store.send(animate: false)
        let mayRetry = await store.checkRetry()
        XCTAssertFalse(mayRetry)
        XCTAssertEqual(service.requests.count, 1)
        service.status = .settled
        let mayGenerateAgain = await store.checkRetry()
        XCTAssertTrue(mayGenerateAgain)
        XCTAssertEqual(service.requests.count, 1)
    }

    func testImmediateStopDoesNotStartInference() async throws {
        let service = RecordingAnswerService()
        let store = ChatStore(service: service)
        store.draft = "Question"
        let task = try XCTUnwrap(store.startSend(animate: false))
        task.cancel()
        await task.value
        XCTAssertTrue(service.requests.isEmpty)
        XCTAssertFalse(store.isSending)
        XCTAssertTrue(store.canRetry)
        XCTAssertEqual(store.errorMessage, "Response stopped.")
    }

    func testStreamErrorsKeepRateLimitAndSourceFailureMeaning() throws {
        for (payload, expected) in [
            (#"{"code":"answer_unavailable","status":429}"#, AnswerServiceError.rateLimited),
            (#"{"code":"sources_unavailable"}"#, AnswerServiceError.sourcesUnavailable),
            (#"{"code":"invalid_answer_format","status":502}"#, AnswerServiceError.invalidResponse)
        ] {
            var parser = AnswerEventParser()
            XCTAssertThrowsError(try parser.consume("data: {\"type\":\"error\",\"error\":\(payload)}")) {
                XCTAssertEqual($0.localizedDescription, expected.localizedDescription)
            }
        }
    }

    func testStartsFreshAndReopensSavedConversationWithFullContext() async throws {
        let storage = LocalConversationStorage(namespace: "account-one", root: root)
        let service = RecordingAnswerService()
        let first = ChatStore(service: service, storage: storage)
        first.draft = "First question"
        await first.send(animate: false)
        let originalID = first.conversation.id
        let restored = ChatStore(service: service, storage: storage)
        XCTAssertTrue(restored.conversation.messages.isEmpty)
        XCTAssertNotEqual(restored.conversation.id, originalID)
        XCTAssertEqual(restored.history.map(\.id), [originalID])
        restored.openConversation(originalID)
        XCTAssertEqual(restored.conversation.id, originalID)
        XCTAssertEqual(restored.conversation.messages.map(\.text), ["First question", "A streamed answer"])
        restored.draft = "Follow up"
        await restored.send(animate: false)
        XCTAssertEqual(service.requests.last?.map(\.text), ["First question", "A streamed answer", "Follow up"])
        XCTAssertEqual(try storage.load(originalID).messages.count, 4)
        XCTAssertEqual(try storage.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testNewConversationsRetainOldChatsAndDeleteOnlySelectedSession() async throws {
        let storage = LocalConversationStorage(namespace: "account-one", root: root)
        let store = ChatStore(service: RecordingAnswerService(), storage: storage)
        store.draft = "First"
        await store.send(animate: false)
        let firstID = store.conversation.id
        store.newConversation()
        store.draft = "Second"
        await store.send(animate: false)
        let secondID = store.conversation.id
        XCTAssertEqual(store.history.count, 2)
        store.openConversation(firstID)
        XCTAssertEqual(store.conversation.messages.first?.text, "First")
        store.deleteConversation(firstID)
        XCTAssertTrue(store.conversation.messages.isEmpty)
        XCTAssertEqual(store.history.map(\.id), [secondID])
        let relaunched = ChatStore(service: RecordingAnswerService(), storage: storage)
        XCTAssertTrue(relaunched.conversation.messages.isEmpty)
        XCTAssertEqual(relaunched.history.map(\.id), [secondID])
        XCTAssertThrowsError(try storage.load(firstID))
    }

    func testIsolatesAccountsAndPreservesUnreadableFiles() throws {
        let one = LocalConversationStorage(namespace: "one", root: root)
        let two = LocalConversationStorage(namespace: "two", root: root)
        var conversation = Conversation()
        conversation.messages = [.question(id: UUID(), text: "Private question")]
        try one.save(conversation)
        XCTAssertTrue(try two.summaries().items.isEmpty)
        let broken = one.directory.appendingPathComponent("broken.json")
        try Data("broken".utf8).write(to: broken)
        XCTAssertEqual(try one.summaries().unreadableCount, 1)
        XCTAssertEqual(try one.summaries().items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path))
    }

    func testInterruptedStreamKeepsQuestionWithoutPublishingPartialAnswer() async throws {
        let storage = LocalConversationStorage(namespace: "one", root: root)
        let service = RecordingAnswerService()
        service.interrupt = true
        let store = ChatStore(service: service, storage: storage)
        store.draft = "Question"
        await store.send(animate: false)
        let restored = ChatStore(service: service, storage: storage)
        restored.openConversation(store.conversation.id)
        XCTAssertEqual(restored.conversation.messages.map(\.text), ["Question"])
        XCTAssertFalse(store.isSending)
        service.interrupt = false
        restored.draft = "Continue"
        await restored.send(animate: false)
        XCTAssertEqual(service.requests.last?.map(\.text), ["Question", "Continue"])
    }

    func testSizeLimitRejectsWithoutDroppingOldMessages() throws {
        var messages = (0..<26).map { _ in ChatMessage.question(id: UUID(), text: String(repeating: "a", count: 8000)) }
        messages.append(.question(id: UUID(), text: "Latest"))
        XCTAssertThrowsError(try ProxyAnswerService.context(from: messages)) { error in
            XCTAssertEqual(error.localizedDescription, AnswerServiceError.conversationTooLong.localizedDescription)
        }
        XCTAssertEqual(messages.count, 27)
    }

    func testStorageFailurePreventsSendingAndKeepsDraft() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blockingFile = root.appendingPathComponent("file")
        try Data("not a directory".utf8).write(to: blockingFile)
        let service = RecordingAnswerService()
        let store = ChatStore(service: service, storage: LocalConversationStorage(namespace: "one", root: blockingFile))
        store.draft = "Keep this question"
        await store.send(animate: false)
        XCTAssertTrue(service.requests.isEmpty)
        XCTAssertEqual(store.draft, "Keep this question")
        XCTAssertTrue(store.conversation.messages.isEmpty)
    }

    func testFailedAnswerSaveBlocksNavigationAndCanRetryWithoutInference() async throws {
        let storage = LocalConversationStorage(namespace: "save-recovery", root: root)
        let service = RecordingAnswerService()
        service.beforeAnswer = {
            // The question was saved; make the destination unwritable for the answer.
            try FileManager.default.removeItem(at: storage.directory)
            try Data("blocking file".utf8).write(to: storage.directory)
        }
        let store = ChatStore(service: service, storage: storage)
        store.draft = "Question"
        await store.send(animate: false)
        let id = store.conversation.id
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertEqual(store.conversation.messages.count, 2)
        store.newConversation()
        XCTAssertEqual(store.conversation.id, id)
        XCTAssertFalse(store.ensureSaved())
        try FileManager.default.removeItem(at: storage.directory)
        XCTAssertTrue(store.retrySave())
        XCTAssertEqual(try storage.load(id).messages.count, 2)
        XCTAssertEqual(service.requests.count, 1)
        store.newConversation()
        XCTAssertNotEqual(store.conversation.id, id)
    }

    func testEventParserRejectsErrorsAndMismatchedCompletion() throws {
        var parser = AnswerEventParser()
        _ = try parser.consume(#"data: {"type":"start"}"#)
        _ = try parser.consume(#"data: {"type":"delta","text":"Hello 🙏"}"#)
        XCTAssertEqual(parser.text, "Hello 🙏")
        XCTAssertThrowsError(try parser.consume(#"data: {"type":"done","answer":{"text":"Different","scripture":[],"commentary":[]}}"#))
        XCTAssertThrowsError(try parser.consume(#"data: {"type":"error","error":{"code":"answer_timeout","message":"private provider detail"}}"#)) { error in
            XCTAssertEqual(error.localizedDescription, AnswerServiceError.timedOut.localizedDescription)
        }
    }

    func testURLSessionReceivesStreamingChunksBeforeCompletion() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StreamingURLProtocol.self]
        let client = ProxyAnswerService(endpoint: URL(string: "https://proxy.example/v1/answers")!,
            accessToken: { "test-session" }, hasConsent: { true }, session: URLSession(configuration: config))
        var updates: [String] = []
        let answer = try await client.streamAnswer(for: [.question(id: UUID(), text: "Hello")]) { text in
            updates.append(text)
            // The mock intentionally holds completion until an incremental update reaches the app.
            StreamingURLProtocol.finish?()
        }
        XCTAssertEqual(updates.first, "Hello 🙏")
        XCTAssertEqual(answer.text, "Hello 🙏")
    }

    func testURLSessionRejectsEOFWithoutDone() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StreamingURLProtocol.self]
        let client = ProxyAnswerService(endpoint: URL(string: "https://proxy.example/v1/answers")!,
            accessToken: { "test-session" }, hasConsent: { true }, session: URLSession(configuration: config))
        do {
            _ = try await client.streamAnswer(for: [.question(id: UUID(), text: "Hello")]) { _ in
                StreamingURLProtocol.endWithoutDone?()
            }
            XCTFail("EOF is not a completed answer")
        } catch { XCTAssertEqual(error.localizedDescription, AnswerServiceError.invalidResponse.localizedDescription) }
    }
}

@MainActor
private final class RecordingAnswerService: AnswerService {
    var requests: [[ChatMessage]] = []
    var interrupt = false
    var failure: AnswerServiceError?
    var beforeAnswer: (() throws -> Void)?
    var status: AnswerAttemptStatus = .notFound
    func requestStatus(for messageID: UUID) async throws -> AnswerAttemptStatus { status }
    func answer(for messages: [ChatMessage]) async throws -> FaithAnswer { fatalError("Must stream") }
    func streamAnswer(for messages: [ChatMessage], onUpdate: @escaping @MainActor (String) -> Void) async throws -> FaithAnswer {
        requests.append(messages)
        onUpdate("A streamed")
        if interrupt { throw CancellationError() }
        if let failure { throw failure }
        try beforeAnswer?()
        onUpdate("A streamed answer")
        return FaithAnswer(text: "A streamed answer", scripture: [], commentary: [])
    }
}

private final class StreamingURLProtocol: URLProtocol, @unchecked Sendable {
    static var finish: (() -> Void)?
    static var endWithoutDone: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        Self.finish = { [weak self] in
            Self.finish = nil
            guard let self else { return }
            self.client?.urlProtocol(self, didLoad: Data("data: {\"type\":\"done\",\"answer\":{\"text\":\"Hello 🙏\",\"scripture\":[],\"commentary\":[]}}\n\n".utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        Self.endWithoutDone = { [weak self] in
            guard let self else { return }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        let data = Data("data: {\"type\":\"start\"}\r\n\r\ndata: {\"type\":\"delta\",\"text\":\"Hello 🙏\"}\r\n\r\n".utf8)
        for byte in data { client?.urlProtocol(self, didLoad: Data([byte])) }
    }
    override func stopLoading() { Self.finish = nil; Self.endWithoutDone = nil }
}
