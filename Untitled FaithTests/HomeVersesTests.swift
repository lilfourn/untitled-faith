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

    func passages(for references: [BibleReference]) async throws -> QuotedPassages {
        requestedReference = references.first
        return QuotedPassages(translation: "ESV", passages: Dictionary(uniqueKeysWithValues: references.map { ($0, Self.text) }))
    }
}
