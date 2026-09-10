import NaturalLanguage
import XCTest
@testable import Untitled_Faith

final class BibleTests: XCTestCase {
    func testParsesCommonReferenceForms() {
        XCTAssertEqual(BibleReference.parse("John 3:16")?.description, "John 3:16")
        XCTAssertEqual(BibleReference.parse("jn. 3:16-18 (ESV)")?.description, "John 3:16–18")
        XCTAssertEqual(BibleReference.parse("1John 4:19")?.description, "1 John 4:19")
        XCTAssertEqual(BibleReference.parse("Psalms 23")?.description, "Psalm 23")
        XCTAssertEqual(BibleReference.parse("Genesis 1:1–2:3")?.description, "Genesis 1:1–2:3")
        XCTAssertEqual(BibleReference.parse("Song of Songs 2:1")?.description, "Song of Solomon 2:1")
        XCTAssertEqual(BibleReference.parse("Prov 3:5-5")?.description, "Proverbs 3:5")
        XCTAssertNil(BibleReference.parse("Hezekiah 3:16"))
        XCTAssertNil(BibleReference.parse("John 3:18-16"))
        XCTAssertNil(BibleReference.parse("John"))
    }

    func testDetectsReferencesInProse() {
        let text = "Jesus said in John 3:16 that God loved the world. See also Rom. 8:28–30, Psalm 23, and 1 Pet 5:7 " +
            "(John 3:16 again). Jobs 3:1, 2:15, and the score of 3:16 are not references, and neither is 'Is 3:16'."
        XCTAssertEqual(ScriptureReferenceDetector.references(in: text).map(\.description),
                       ["John 3:16", "Romans 8:28–30", "Psalm 23", "1 Peter 5:7"])
    }

    func testBundledStoreQuotesExactText() throws {
        let store = try XCTUnwrap(BibleStore.bundled)
        XCTAssertEqual(store.translation.id, "BSB")
        let verse = try XCTUnwrap(BibleReference.parse("1 John 4:19"))
        XCTAssertEqual(try store.passage(verse), "We love because He first loved us.")
        let range = try XCTUnwrap(BibleReference.parse("Psalm 23:1-2"))
        XCTAssertTrue(try XCTUnwrap(store.passage(range)).hasPrefix("¹ A Psalm of David. The LORD is my shepherd; I shall not want. ² He makes"))
        XCTAssertEqual(try store.verses(in: XCTUnwrap(BibleReference.parse("Psalm 117"))).count, 2)
        XCTAssertEqual(try store.verses(in: XCTUnwrap(BibleReference.parse("Genesis 1:31–2:2"))).map(\.reference.description),
                       ["Genesis 1:31", "Genesis 2:1", "Genesis 2:2"])
        XCTAssertNil(try store.passage(XCTUnwrap(BibleReference.parse("Jude 2:1"))))
        let citation = try XCTUnwrap(store.citation(verse))
        XCTAssertEqual(citation.reference, "1 John 4:19")
        XCTAssertEqual(citation.translation, "BSB")
        XCTAssertEqual(try store.allVerses().count, 31_086)
    }

    func testFullTextSearchFindsWordsAndExactPhrases() throws {
        let store = try XCTUnwrap(BibleStore.bundled)
        XCTAssertEqual(try store.search(phrase: "my shepherd").first?.reference.description, "Psalm 23:1")
        XCTAssertTrue(try store.search(words: "faith hope love").contains { $0.reference.description == "1 Corinthians 13:13" })
        XCTAssertEqual(try store.search(phrase: "\"the shepherd my\""), [])
        XCTAssertEqual(try store.search(words: "  ,; "), [])
    }

    func testSemanticIndexRoundTripsAndFindsRelatedVerses() throws {
        let store = try XCTUnwrap(BibleStore.bundled)
        guard let index = VerseEmbeddingIndex() else { throw XCTSkip("Sentence embeddings are unavailable on this simulator") }
        index.index(try store.verses(in: XCTUnwrap(BibleReference.parse("Psalm 20:1–30:12"))))
        XCTAssertEqual(index.count, 149, "Psalms 20–30 hold 149 verses")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = VerseEmbeddingIndex.cacheURL(translation: store.translation.id, directory: directory)
        try index.write(to: url)
        let loaded = try XCTUnwrap(VerseEmbeddingIndex())
        try loaded.read(from: url)
        XCTAssertEqual(loaded.count, index.count)
        let matches = loaded.search("The Lord cares for me like a shepherd cares for sheep", limit: 5)
        XCTAssertEqual(matches.count, 5)
        XCTAssertTrue(matches.contains { $0.reference.book.name == "Psalm" && $0.reference.chapter == 23 },
                      "Expected Psalm 23 among \(matches.map { "\($0.reference) \($0.score)" })")
    }
}
