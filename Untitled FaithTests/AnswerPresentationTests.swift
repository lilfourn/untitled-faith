import SwiftUI
import XCTest
@testable import Untitled_Faith

@MainActor
final class AnswerPresentationTests: XCTestCase {
    func testThinkingThenWritingDoesNotPublishIncompleteText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LocalConversationStorage(namespace: "presentation", root: root)
        let service = HeldAnswerService()
        let started = expectation(description: "Request started")
        service.onStart = { started.fulfill() }
        let store = ChatStore(service: service, storage: storage)
        store.draft = "Question"
        let task = Task { await store.send(animate: false) }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(store.loadingPhase, .thinking)
        service.onUpdate?("An incomplete **answer")
        XCTAssertEqual(store.loadingPhase, .writing)
        XCTAssertEqual(store.conversation.messages.map(\.text), ["Question"])
        XCTAssertEqual(try storage.load(store.conversation.id).messages.count, 1)
        service.completion?.resume(returning: FaithAnswer(text: "A **complete** answer", scripture: [], commentary: []))
        await task.value
        XCTAssertNil(store.loadingPhase)
        XCTAssertNil(store.revealProgress)
        XCTAssertEqual(store.conversation.messages.last?.text, "A **complete** answer")
    }

    func testStoppingTheRevealKeepsTheCompleteSavedAnswer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LocalConversationStorage(namespace: "presentation", root: root)
        let service = HeldAnswerService()
        let started = expectation(description: "Request started")
        service.onStart = { started.fulfill() }
        let store = ChatStore(service: service, storage: storage)
        store.draft = "Question"
        let task = Task { await store.send() }
        await fulfillment(of: [started], timeout: 2)
        let answer = FaithAnswer(text: "A complete answer that is saved before its presentation finishes.", scripture: [], commentary: [])
        service.completion?.resume(returning: answer)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(store.isSending)
        XCTAssertNotNil(store.revealingMessageID)
        XCTAssertEqual(try storage.load(store.conversation.id).messages.last?.text, answer.text)
        task.cancel()
        await task.value
        XCTAssertFalse(store.isSending)
        XCTAssertNil(store.revealProgress)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.conversation.messages.last?.text, answer.text)
    }

    func testRenderLoadingAndMarkdownForReview() throws {
        let answer = FaithAnswer(text: """
        ## Begin with one Gospel

        Start with **John** and take your time. A little reading *each day* is enough.

        ### A simple rhythm

        1. Read a short passage.
        2. Write down one question.
           - Notice what it says about Jesus.
           - Return to the passage tomorrow.

        | Day | Reading |
        | --- | --- |
        | Monday | John 1 |
        | Tuesday | John 2 |

        ```text
        Read → reflect → pray
        ```
        """, scripture: [], commentary: [])
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: VStack(alignment: .leading, spacing: 24) {
                ThinkingText(title: "Thinking…")
                ThinkingText(title: "Writing…")
                Divider()
                AnswerTextView(answer: answer)
            }.padding(24).frame(width: 390).background(AppTheme.background).environment(\.colorScheme, scheme))
            renderer.scale = 2
            let data = try XCTUnwrap(renderer.uiImage?.pngData())
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("answer-presentation-\(scheme == .light ? "light" : "dark").png")
            try data.write(to: file)
            print("Answer presentation preview: \(file.path)")
        }
    }
}

@MainActor
private final class HeldAnswerService: AnswerService {
    var onStart: () -> Void = {}
    var onUpdate: (@MainActor (String) -> Void)?
    var completion: CheckedContinuation<FaithAnswer, Error>?
    func answer(for messages: [ChatMessage]) async throws -> FaithAnswer { fatalError("Use streaming") }
    func streamAnswer(for messages: [ChatMessage], onUpdate: @escaping @MainActor (String) -> Void) async throws -> FaithAnswer {
        self.onUpdate = onUpdate
        return try await withCheckedThrowingContinuation { completion in
            self.completion = completion
            onStart()
        }
    }
}
