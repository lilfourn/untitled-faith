import SwiftUI
import XCTest
@testable import Untitled_Faith

@MainActor
final class QuotationPresentationTests: XCTestCase {
    func testPreviewKeepsShortQuotesAndTruncatesLongQuotesWithoutSplittingUnicode() {
        for count in [0, 199, 200] {
            let text = String(repeating: "a", count: count)
            XCTAssertEqual(QuotationPreview(text).text, text)
            XCTAssertFalse(QuotationPreview(text).isTruncated)
        }
        let text = String(repeating: "🙏🏽", count: 201)
        let preview = QuotationPreview(text)
        XCTAssertTrue(preview.isTruncated)
        XCTAssertEqual(preview.text.count, 200)
        XCTAssertTrue(preview.text.hasSuffix("…"))
        XCTAssertEqual(String(preview.text.dropLast()), String(text.prefix(199)))
    }

    func testLongVerifiedQuotationDecodesAndPersistsInFull() throws {
        let sourceID = UUID()
        let quote = String(repeating: "A longer passage for reading. ", count: 80)
        let url = "https://www.esv.org/Luke+11/"
        let answerText = "> [Scripture] \(quote)\n[Luke 11 — ESV](\(url))\n"
        let data: [String: Any] = ["text": answerText, "scripture": [], "commentary": [],
            "sources": [["id": sourceID.uuidString, "url": url, "title": "Luke 11 — ESV", "kind": "scripture"]],
            "quotes": [["id": UUID().uuidString, "text": quote, "attribution": "Luke 11 — ESV",
                        "sourceID": sourceID.uuidString, "startIndex": 0, "endIndex": answerText.utf16.count]]]
        let payload = try JSONDecoder().decode(AnswerPayload.self, from: JSONSerialization.data(withJSONObject: data))
        let answer = try payload.validatedAnswer()
        let restored = try JSONDecoder().decode(FaithAnswer.self, from: JSONEncoder().encode(answer))
        XCTAssertEqual(restored.quotes?.first?.text, quote)
        XCTAssertEqual(restored.text, answerText)
        XCTAssertTrue(QuotationPreview(quote).isTruncated)
        XCTAssertLessThanOrEqual(QuotationPreview(quote).text.count, 200)
    }

    func testRenderQuotePreview() throws {
        let passage = """
        Ask, and it will be given to you; seek, and you will find; knock, and the door will be opened to you.

        For everyone who asks receives; he who seeks finds; and to him who knocks, the door will be opened.

        What father among you, if his son asks for a fish, will give him a snake instead? Or if he asks for an egg, will give him a scorpion?
        """
        let sourceURL = URL(string: "https://www.bible.com/bible/3034/LUK.11.9-12")!
        for scheme in [ColorScheme.light, .dark] {
            let card = QuotationCard(text: passage, attribution: "Luke 11:9–12 — BSB", kind: .scripture, sourceURL: sourceURL)
            let renderer = ImageRenderer(content: card.padding(24).frame(width: 390)
                .background(AppTheme.background).environment(\.colorScheme, scheme))
            renderer.scale = 2
            let data = try XCTUnwrap(renderer.uiImage?.pngData())
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("quotation-card-\(scheme == .light ? "light" : "dark").png")
            try data.write(to: file)
            print("Quotation preview: \(file.path)")
        }
    }
}
