import XCTest
@testable import Untitled_Faith

final class AnswerSourceListTests: XCTestCase {
    private func source(_ title: String, _ url: String, kind: AnswerSource.Kind = .scripture) -> AnswerSource {
        AnswerSource(id: UUID(), title: title, url: URL(string: url)!, kind: kind)
    }

    func testSamePassageAndTranslationAcrossPublishersHasOneSourceEntry() {
        let sources = [
            source("John 3:16 — ESV", "https://www.esv.org/John%203%3A16/"),
            source("John 3:16 - ESV", "https://www.biblegateway.com/passage/?search=John+3%3A16&version=ESV"),
            source("John 3:16", "https://www.bible.com/bible/59/JHN.3.16.ESV"),
            source("John 3:16", "https://esv.org/John+3:16/#text"),
        ]
        XCTAssertEqual(AnswerSourceList.unique(sources).map(\.id), [sources[0].id])
        XCTAssertEqual(sources.count, 4, "Other cards retain their original source IDs and exact links")
    }

    func testRepeatedVerseFromAChapterAndAVerseURLHasOneSourceEntry() {
        let sources = [
            source("John 3 — ESV", "https://www.esv.org/John+3/"),
            source("John 3:16 — ESV", "https://www.biblegateway.com/passage/?search=John+3%3A16&version=ESV"),
        ]
        let quotes = sources.map { source in
            AnswerQuote(id: UUID(), text: "Verified wording.", attribution: "John 3:16 - ESV", sourceID: source.id, startIndex: 0, endIndex: 20)
        }
        XCTAssertEqual(AnswerSourceList.unique(sources, quotes: quotes).map(\.id), [sources[0].id])
        XCTAssertEqual(quotes.map(\.sourceID), sources.map(\.id))
    }

    func testDifferentVersesRangesAndTranslationsRemainDistinct() {
        let sources = [
            source("John 3:16 — ESV", "https://www.esv.org/John+3:16/"),
            source("John 3:17 — ESV", "https://www.esv.org/John+3:17/"),
            source("John 3:16–18 — ESV", "https://www.esv.org/John+3:16-18/"),
            source("John 3:16 — BSB", "https://www.bible.com/bible/3034/JHN.3.16"),
        ]
        XCTAssertEqual(AnswerSourceList.unique(sources).map(\.id), sources.map(\.id))
    }

    func testCanonicalAliasesAndCrossChapterRangesDeduplicate() {
        let sources = [
            source("Psalms 23:1–3 — ESV", "https://www.esv.org/Psalms+23:1-3/"),
            source("Psalm 23:1-3 — ESV", "https://www.biblegateway.com/passage/?search=Psalm+23%3A1-3&version=ESV"),
            source("John 3:16–4:3 — ESV", "https://www.esv.org/John+3:16-4:3/"),
            source("John 3:16–4:3 — ESV", "https://www.bible.com/bible/59/JHN.3.16-4.3.ESV"),
        ]
        XCTAssertEqual(AnswerSourceList.unique(sources).map(\.id), [sources[0].id, sources[2].id])
    }

    func testCommentaryUsesURLIdentityAndDoesNotCollapseDifferentArticles() {
        let sources = [
            source("John 3:16 explained", "https://www.gotquestions.org/John-3-16.html", kind: .commentary),
            source("Another title", "https://gotquestions.org/John-3-16.html#section", kind: .commentary),
            source("John 3:16 explained", "https://bibleproject.com/articles/john/", kind: .commentary),
        ]
        XCTAssertEqual(AnswerSourceList.unique(sources).map(\.id), [sources[0].id, sources[2].id])
    }
}
