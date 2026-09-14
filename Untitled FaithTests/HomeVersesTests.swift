import XCTest
@testable import Untitled_Faith

final class HomeVersesTests: XCTestCase {
    func testRandomVersesUseExactESVResponseAndDoNotRepeat() async throws {
        let service = StubESVService()
        let quoter = ScriptureQuoter(service: service, cache: nil, fallback: BibleStore.bundled)
        var lastReference = "John 3:16"
        for _ in 0..<20 {
            let result = await HomeVerses.random(excluding: lastReference, quoter: quoter)
            let verse = try XCTUnwrap(result)
            XCTAssertNotEqual(verse.reference, lastReference)
            XCTAssertEqual(verse.translation, "ESV")
            XCTAssertEqual(verse.reference, service.requestedReference?.description)
            XCTAssertEqual(verse.passage, StubESVService.text)
            lastReference = verse.reference
        }
    }

    func testPoolServesThirtyDrawsWithOneBatchAndSurvivesRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = StubESVService()
        let cache = PassageCache(directory: directory)
        let quoter = ScriptureQuoter(service: service, cache: cache, fallback: BibleStore.bundled)
        var last = ""
        for _ in 0..<30 {
            let result = await HomeVerses.random(excluding: last, quoter: quoter)
            let verse = try XCTUnwrap(result)
            XCTAssertNotEqual(verse.reference, last)
            XCTAssertEqual(verse.translation, "ESV")
            XCTAssertEqual(verse.passage, StubESVService.text)
            last = verse.reference
        }
        XCTAssertEqual(service.calls, 1)
        XCTAssertEqual(cache.storedVerses, 8)
        let offline = ScriptureQuoter(service: nil, cache: PassageCache(directory: directory), fallback: BibleStore.bundled)
        let restored = await HomeVerses.random(excluding: last, quoter: offline)
        XCTAssertNotNil(restored)
        XCTAssertNotEqual(restored?.reference, last)
        XCTAssertEqual(restored?.translation, "ESV")
    }

    func testHomeCacheExcludesRangesOtherTranslationsAndLastVerse() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PassageCache(directory: directory)
        cache.store("¹ one ² two", translation: "ESV", for: try XCTUnwrap(BibleReference.parse("John 1:1-2")))
        cache.store("BSB text", translation: "BSB", for: try XCTUnwrap(BibleReference.parse("John 1:3")))
        cache.store("ESV text", translation: "ESV", for: try XCTUnwrap(BibleReference.parse("John 1:4")))
        XCTAssertNil(cache.randomVerse(excluding: "John 1:4"))
        XCTAssertEqual(cache.randomVerse(excluding: "")?.reference, "John 1:4")
    }

    func testUnavailableESVDoesNotDisplayBundledBSB() async {
        let quoter = ScriptureQuoter(service: nil, cache: nil, fallback: BibleStore.bundled)
        let result = await HomeVerses.random(excluding: "John 3:16", quoter: quoter)
        XCTAssertNil(result)
    }
}

private final class StubESVService: PassageFetching {
    // Synthetic service text verifies verbatim forwarding without embedding Scripture wording.
    static let text = "Exact service text, including punctuation."
    var requestedReference: BibleReference?
    var calls = 0

    func passages(for references: [BibleReference]) async throws -> QuotedPassages {
        calls += 1
        requestedReference = references.first
        return QuotedPassages(translation: "ESV", passages: Dictionary(uniqueKeysWithValues: references.map { ($0, Self.text) }))
    }
}
