import XCTest
@testable import Untitled_Faith

final class AnswerBodyTests: XCTestCase {
    private func citation(_ reference: String, translation: String = "ESV") -> ScriptureCitation {
        ScriptureCitation(id: UUID(), reference: reference, translation: translation, passage: "Verified text for \(reference).")
    }

    func testPlacesEachFetchedVerseAtItsFirstParagraphAndPreservesTheAnswer() {
        let text = "🙏 John 3:16 introduces the point.\n\nRomans 8:28 develops it.\n\nReturn to John 3:16."
        let john = citation("John 3:16")
        let romans = citation("Romans 8:28", translation: "BSB")
        let answer = FaithAnswer(text: text, scripture: [john, romans, citation("John 3:16")], commentary: [])
        let blocks = AnswerBody.blocks(for: answer)
        XCTAssertEqual(blocks.count, 5)
        XCTAssertTrue(blocks[0].text.hasPrefix("🙏 John 3:16"))
        XCTAssertEqual(blocks[1].scripture?.id, john.id)
        XCTAssertTrue(blocks[2].text.hasPrefix("Romans 8:28"))
        XCTAssertEqual(blocks[3].scripture?.id, romans.id)
        XCTAssertEqual(blocks.filter { $0.scripture == nil }.map(\.text).joined(), text)
        XCTAssertEqual(Set(blocks.map(\.id)).count, blocks.count)
    }

    func testExistingVerifiedCardSuppressesTheOldExtraCardAndCoversContainedVerses() {
        let source = AnswerSource(id: UUID(), title: "John 3:16–18 — ESV", url: URL(string: "https://www.esv.org/John+3:16-18/")!, kind: .scripture)
        let first = "> [Scripture] Verified passage.\n[John 3:16–18 - ESV](\(source.url))\n"
        let text = first + "\nJohn 3:16 is part of this passage. Romans 8:28 is another passage."
        let quote = AnswerQuote(id: UUID(), text: "Verified passage.", attribution: "John 3:16–18 - ESV", sourceID: source.id,
                                startIndex: 0, endIndex: first.utf16.count)
        let answer = FaithAnswer(text: text, scripture: [citation("John 3:16"), citation("John 3:16–18")], commentary: [], sources: [source], quotes: [quote])
        XCTAssertEqual(AnswerScripture.missingReferences(in: answer).map(\.description), ["Romans 8:28"])
        let blocks = AnswerBody.blocks(for: answer)
        XCTAssertEqual(blocks.compactMap(\.quote).map(\.sourceID), [source.id])
        XCTAssertTrue(blocks.compactMap(\.scripture).isEmpty)
    }

    func testFillsOnlyMissingCardsWhenSomeCitationsAlreadyExist() {
        let answer = FaithAnswer(text: "John 3:16 and Romans 8:28. John 3:16 again.", scripture: [citation("John 3:16")], commentary: [])
        XCTAssertEqual(AnswerScripture.missingReferences(in: answer).map(\.description), ["Romans 8:28"])
    }

    func testKeepsListsAndFencedBlocksIntactAroundInsertedCards() {
        let list = "1. Read John 3:16.\n\n2. Reflect on the passage.\n\n"
        let code = "```text\nJohn 3:16\n\nA separate line.\n```\n\n"
        for markdown in [list, code] {
            let answer = FaithAnswer(text: markdown + "A final paragraph.", scripture: [citation("John 3:16")], commentary: [])
            let blocks = AnswerBody.blocks(for: answer)
            XCTAssertEqual(blocks[0].text, markdown)
            XCTAssertEqual(blocks[1].scripture?.reference, "John 3:16")
            XCTAssertEqual(blocks[2].text, "A final paragraph.")
        }
    }

    func testIncompleteAnswersDoNotRenderUnverifiedCards() {
        let answer = FaithAnswer(text: "John 3:16", scripture: [citation("John 3:16")], commentary: [], isComplete: false)
        XCTAssertEqual(AnswerBody.blocks(for: answer).count, 1)
        XCTAssertNil(AnswerBody.blocks(for: answer).first?.scripture)
    }
}
