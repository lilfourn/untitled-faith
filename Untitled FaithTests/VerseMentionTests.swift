import XCTest
@testable import Untitled_Faith

@MainActor
final class VerseMentionTests: XCTestCase {
    private func citation(_ reference: String = "1 John 4:19", passage: String = "We love because He first loved us.") -> ScriptureCitation {
        ScriptureCitation(id: UUID(), reference: reference, translation: "BSB", passage: passage)
    }

    func testMentionReplacementPreservesUnicodeAndProseAfterCaret() throws {
        let prefix = "🙏 Compare @1 Jo"
        let draft = prefix + " with Romans 8:28."
        let query = try XCTUnwrap(VerseMentionQuery.active(in: draft, selection: NSRange(location: prefix.utf16.count, length: 0)))
        XCTAssertEqual(query.text, "1 Jo")
        let inserted = try XCTUnwrap(query.inserting("1 John 4:19", in: draft))
        XCTAssertEqual(inserted.text, "🙏 Compare 1 John 4:19 with Romans 8:28.")
        XCTAssertEqual(inserted.selection.location, "🙏 Compare 1 John 4:19".utf16.count)
        XCTAssertNil(query.inserting("1 John 4:19", in: "A different draft"))
    }

    func testSearchIgnoresEmailsSelectionsAndEarlierLines() {
        for text in ["luke@example.com", "@John\nExplain this", "prefix@John"] {
            XCTAssertNil(VerseMentionQuery.active(in: text, selection: NSRange(location: text.utf16.count, length: 0)))
        }
        XCTAssertNil(VerseMentionQuery.active(in: "@John", selection: NSRange(location: 1, length: 2)))
        XCTAssertNil(VerseMentionQuery.active(in: "@John", selection: NSRange(location: 100, length: 0)))
        XCTAssertEqual(VerseMentionQuery.active(in: "@", selection: NSRange(location: 1, length: 0))?.text, "")
    }

    func testLocalSearchSupportsBooksReferencesRangesAndPartialWords() throws {
        let search = VerseSearch(bible: try XCTUnwrap(BibleStore.bundled))
        XCTAssertEqual(try search.results(for: "").count, 4)
        XCTAssertTrue(try search.results(for: "jo").contains { $0.reference == "John 1:1" })
        XCTAssertEqual(search.exactResult(for: "1John4:19")?.passage, "We love because He first loved us.")
        XCTAssertEqual(search.exactResult(for: "jn.3:16")?.reference, "John 3:16")
        XCTAssertEqual(search.exactResult(for: "Psalm 23:1-2")?.translation, "BSB")
        XCTAssertEqual(try search.results(for: "John 3:").first?.reference, "John 3:1")
        XCTAssertTrue(try search.results(for: "my shepher").contains { $0.reference == "Psalm 23:1" })
        XCTAssertNil(search.exactResult(for: "John 3:999"))
        XCTAssertNil(search.exactResult(for: "John 3:16-999"))
        XCTAssertNil(search.exactResult(for: "John 999"))
        XCTAssertNil(search.exactResult(for: "John 3 what"))
        XCTAssertTrue(try search.results(for: "\" * -").isEmpty)
    }

    func testCompleteTypedMentionsAreAttachedEvenWithoutSelectingAResult() async throws {
        let draft = "Compare @1John4:19 and @John 3:16 with love."
        XCTAssertEqual(VerseMentionQuery.references(in: draft).map(\.description), ["1 John 4:19", "John 3:16"])
        XCTAssertNil(VerseMentionQuery.active(in: draft, selection: NSRange(location: draft.utf16.count, length: 0)))
        XCTAssertTrue(VerseMentionQuery.references(in: "me@John3:16 @John 3:16-").isEmpty)
        let service = VerseRecordingService()
        let store = ChatStore(service: service)
        store.draft = draft
        await store.send(animate: false)
        let sent = try XCTUnwrap(service.prompts.first?.last)
        XCTAssertTrue(sent.contains("1 John 4:19 (BSB)\nWe love because He first loved us."))
        XCTAssertTrue(sent.contains("John 3:16 (BSB)\n"))
        store.draft = "Explain @John 3:999"
        XCTAssertNil(store.startSend(animate: false))
        XCTAssertEqual(service.prompts.count, 1)
    }

    func testSelectedPassageIsInActualRequestBodyAndPriorContext() async throws {
        let selected = citation()
        let message = ChatMessage.question(id: UUID(), text: "Explain this", scripture: [selected])
        let service = ProxyAnswerService(endpoint: URL(string: "https://example.com/v1/answers")!, accessToken: { "test-token" })
        let request = try await service.makeRequest([message], accept: "text/event-stream")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages[0]["content"], "Explain this\n\nAttached Scripture:\n1 John 4:19 (BSB)\nWe love because He first loved us.")
        let context = try ProxyAnswerService.context(from: [message, .answer(id: UUID(), answer: FaithAnswer(text: "Answer", scripture: [], commentary: [])), .question(id: UUID(), text: "And why?")])
        XCTAssertEqual(context[0].content, messages[0]["content"])
        XCTAssertEqual(message.text, "Explain this")
    }

    func testLegacyQuestionsDecodeAndAttachmentsSurviveStorageAndRetry() async throws {
        let legacy = Data(#"{"question":{"id":"11111111-1111-1111-1111-111111111111","text":"An older question"}}"#.utf8)
        let old = try JSONDecoder().decode(ChatMessage.self, from: legacy)
        XCTAssertEqual(old.promptText, "An older question")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LocalConversationStorage(namespace: "verse-mentions", root: root)
        let service = VerseRecordingService()
        let store = ChatStore(service: service, storage: storage)
        store.draft = "Explain this"
        let revision = store.draftRevision
        XCTAssertTrue(store.attachScripture(citation(), revision: revision))
        let task = try XCTUnwrap(store.startSend(animate: false))
        XCTAssertTrue(store.draftScripture.isEmpty)
        XCTAssertFalse(store.attachScripture(citation("John 3:16"), revision: revision))
        await task.value
        let sent = try XCTUnwrap(service.prompts.first?.first)
        let restored = ChatStore(service: service, storage: storage)
        restored.openConversation(store.conversation.id)
        XCTAssertEqual(restored.conversation.messages.first?.promptText, sent)
        restored.draft = "A later draft"
        restored.attachScripture(citation("Romans 8:28"), revision: restored.draftRevision)
        await (try XCTUnwrap(restored.startSend(animate: false, retrying: true))).value
        XCTAssertEqual(service.prompts.last?.first, sent)
        XCTAssertEqual(restored.draft, "A later draft")
        XCTAssertEqual(restored.draftScripture.first?.reference, "Romans 8:28")
    }

    func testRemovedDuplicateAndOversizedAttachmentsNeverLeakIntoSend() async throws {
        let service = VerseRecordingService()
        let store = ChatStore(service: service)
        let selected = citation()
        store.attachScripture(selected, revision: store.draftRevision)
        store.attachScripture(citation(), revision: store.draftRevision)
        XCTAssertEqual(store.draftScripture.count, 1)
        XCTAssertTrue(store.canSend, "A verse can be sent without extra prose")
        store.removeScripture(selected.id)
        XCTAssertFalse(store.canSend)
        store.draft = "Question"
        store.attachScripture(citation(passage: String(repeating: "x", count: 8000)), revision: store.draftRevision)
        XCTAssertNil(store.startSend(animate: false))
        XCTAssertEqual(store.draft, "Question")
        XCTAssertEqual(store.draftScripture.count, 1)
        XCTAssertTrue(service.prompts.isEmpty)
        store.newConversation()
        XCTAssertTrue(store.draftScripture.isEmpty)
    }
}

@MainActor
private final class VerseRecordingService: AnswerService {
    var prompts: [[String]] = []
    func answer(for messages: [ChatMessage]) async throws -> FaithAnswer {
        prompts.append(try ProxyAnswerService.context(from: messages).map(\.content))
        throw AnswerServiceError.unavailable
    }
}
