import SwiftUI
import XCTest
@testable import Untitled_Faith

@MainActor
final class AnswerSourceTests: XCTestCase {
    private let sourceID = UUID()
    private let quoteID = UUID()
    private let sourceURL = "https://www.gotquestions.org/what-is-prayer.html"

    private func payload() -> [String: Any] {
        let text = "> [Commentary] A short explanation.\n[GotQuestions](\(sourceURL))\n"
        return ["text": text, "scripture": [], "commentary": [],
            "sources": [["id": sourceID.uuidString, "url": sourceURL, "title": "What is prayer?", "kind": "commentary"]],
            "quotes": [["id": quoteID.uuidString, "text": "A short explanation.", "attribution": "GotQuestions",
                "sourceID": sourceID.uuidString, "startIndex": 0, "endIndex": text.utf16.count]]]
    }

    func testStreamingDonePreservesLinksAndQuoteFormattingMetadata() throws {
        let data = payload()
        var parser = AnswerEventParser()
        _ = try parser.consume(#"data: {"type":"start"}"#)
        _ = try parser.consume("data: " + String(decoding: JSONSerialization.data(withJSONObject: ["type": "delta", "text": data["text"]!]), as: UTF8.self))
        let final = try parser.consume("data: " + String(decoding: JSONSerialization.data(withJSONObject: ["type": "done", "answer": data]), as: UTF8.self))
        guard case .done(let answer) = final else { return XCTFail("Missing answer") }
        XCTAssertEqual(answer.sources?.first?.kind, .commentary)
        XCTAssertEqual(answer.quotes?.first?.sourceID, sourceID)
        XCTAssertEqual(answer.sources?.first?.url.absoluteString, sourceURL)
        let restored = try JSONDecoder().decode(FaithAnswer.self, from: JSONEncoder().encode(answer))
        XCTAssertEqual(restored.quotes?.first?.text, "A short explanation.")
    }

    func testOldLocalChatsWithoutSearchMetadataStillDecode() throws {
        let data = Data(#"{"text":"Saved answer","scripture":[],"commentary":[],"isComplete":true}"#.utf8)
        let answer = try JSONDecoder().decode(FaithAnswer.self, from: data)
        XCTAssertEqual(answer.text, "Saved answer")
        XCTAssertNil(answer.sources)
        XCTAssertNil(answer.quotes)
    }

    func testRejectsUnsafeLinksAndInvalidQuoteOffsets() throws {
        for url in ["https://gotquestions.org.evil.example/page", "https://gotquestions.org@evil.example/page", "http://gotquestions.org/page", "javascript:alert(1)"] {
            XCTAssertNil(AnswerSource.canonicalURL(URL(string: url)!))
        }
        var invalid = payload()
        invalid["quotes"] = [["id": quoteID.uuidString, "text": "Quote", "attribution": "Author",
            "sourceID": sourceID.uuidString, "startIndex": 0, "endIndex": 99999]]
        let value = try JSONDecoder().decode(AnswerPayload.self, from: JSONSerialization.data(withJSONObject: invalid))
        XCTAssertThrowsError(try value.validatedAnswer())
    }

    func testRendersScriptureAndCommentaryForVisualReview() throws {
        let scriptureID = UUID()
        let commentaryID = UUID()
        let first = "> [Scripture] The LORD is my shepherd.\n[Psalm 23:1 — KJV](https://www.biblegateway.com/passage/?search=Psalm+23&version=KJV)\n"
        let second = "> [Commentary] An example of a short, attributed explanation.\n[GotQuestions](\(sourceURL))\n"
        let answer = FaithAnswer(text: first + "\nA passage can be followed by a separate explanation.\n\n" + second, scripture: [], commentary: [], sources: [
            AnswerSource(id: scriptureID, title: "Psalm 23 — KJV", url: URL(string: "https://www.biblegateway.com/passage/?search=Psalm+23&version=KJV")!, kind: .scripture),
            AnswerSource(id: commentaryID, title: "Example commentary source", url: URL(string: sourceURL)!, kind: .commentary)
        ], quotes: [
            AnswerQuote(id: UUID(), text: "The LORD is my shepherd.", attribution: "Psalm 23:1 — KJV", sourceID: scriptureID, startIndex: 0, endIndex: first.utf16.count),
            AnswerQuote(id: UUID(), text: "An example of a short, attributed explanation.", attribution: "GotQuestions", sourceID: commentaryID,
                startIndex: (first + "\nA passage can be followed by a separate explanation.\n\n").utf16.count,
                endIndex: (first + "\nA passage can be followed by a separate explanation.\n\n" + second).utf16.count)
        ])
        let renderer = ImageRenderer(content: AnswerTextView(answer: answer).padding(24).frame(width: 390).background(AppTheme.background))
        renderer.scale = 2
        let data = try XCTUnwrap(renderer.uiImage?.pngData())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("answer-sources-preview.png")
        try data.write(to: file)
        print("Source formatting preview: \(file.path)")
    }
}
