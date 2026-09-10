import XCTest
@testable import Untitled_Faith

final class ScriptureQuoterTests: XCTestCase {
    private var directory: URL!
    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    private final class StubService: PassageFetching {
        var responses: [BibleReference: String]
        var calls = 0
        var failing = false
        init(_ responses: [BibleReference: String]) { self.responses = responses }
        func passages(for references: [BibleReference]) async throws -> QuotedPassages {
            calls += 1
            if failing { throw PassageServiceError.unavailable }
            return QuotedPassages(translation: "ESV", passages: responses.filter { references.contains($0.key) })
        }
    }

    func testPrefersLicensedTextThenCacheThenBundledFallback() async throws {
        let john = try XCTUnwrap(BibleReference.parse("John 3:16"))
        let romans = try XCTUnwrap(BibleReference.parse("Romans 8:28"))
        let service = StubService([john: "For God so loved the world, that he gave his only Son."])
        let cache = PassageCache(directory: directory)
        let quoter = ScriptureQuoter(service: service, cache: cache, fallback: try XCTUnwrap(BibleStore.bundled))

        let first = await quoter.citations(for: [john, romans, john])
        XCTAssertEqual(first.map(\.reference), ["John 3:16", "Romans 8:28"])
        XCTAssertEqual(first.map(\.translation), ["ESV", "BSB"])
        XCTAssertEqual(first[0].passage, "For God so loved the world, that he gave his only Son.")
        XCTAssertTrue(first[1].passage.hasPrefix("And we know that God works all things together"))
        XCTAssertEqual(service.calls, 1)

        service.failing = true
        let second = await quoter.citations(for: [john, romans])
        XCTAssertEqual(second.map(\.translation), ["ESV", "BSB"], "John 3:16 comes from the cache; Romans falls back")
        XCTAssertEqual(service.calls, 2)
        XCTAssertEqual(PassageCache(directory: directory).passage(for: john)?.text, first[0].passage, "Cache persists to disk")
    }

    func testWithoutServiceUsesBundledTranslationOnly() async throws {
        let quoter = ScriptureQuoter(service: nil, cache: nil, fallback: try XCTUnwrap(BibleStore.bundled))
        let citations = await quoter.citations(for: [try XCTUnwrap(BibleReference.parse("1 John 4:19")), try XCTUnwrap(BibleReference.parse("Jude 9:9"))])
        XCTAssertEqual(citations.map { "\($0.reference) \($0.translation)" }, ["1 John 4:19 BSB"])
    }

    func testCacheEvictsLeastRecentlyUsedBeyondVerseLimit() throws {
        let cache = PassageCache(directory: directory, verseLimit: 5)
        let a = try XCTUnwrap(BibleReference.parse("Psalm 1:1-3"))
        let b = try XCTUnwrap(BibleReference.parse("Psalm 2:1-2"))
        let c = try XCTUnwrap(BibleReference.parse("Psalm 3:1"))
        cache.store("¹ one ² two ³ three", translation: "ESV", for: a)
        cache.store("¹ one ² two", translation: "ESV", for: b)
        XCTAssertEqual(cache.storedVerses, 5)
        _ = cache.passage(for: a)  // a is now more recent than b
        cache.store("single", translation: "ESV", for: c)
        XCTAssertNil(cache.passage(for: b))
        XCTAssertNotNil(cache.passage(for: a))
        XCTAssertEqual(cache.storedVerses, 4)
        cache.store(String(repeating: "¹ x ", count: 6), translation: "ESV", for: c)
        XCTAssertEqual(cache.passage(for: c)?.text, "single", "Passages over the limit are never stored")
        XCTAssertEqual(PassageCache.verseCount(in: "¹² a ¹³ b"), 2)
    }
}
