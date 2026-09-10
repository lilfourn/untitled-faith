import XCTest
@testable import Untitled_Faith

final class HomeVersesTests: XCTestCase {
    func testVersesAreCompleteESVQuotationsWithinCrosswayLimits() {
        let verses = HomeVerses.esv
        XCTAssertFalse(verses.isEmpty)
        XCTAssertLessThan(verses.count, 1000)
        XCTAssertEqual(Set(verses.map(\.reference)).count, verses.count, "References should be unique")
        for verse in verses {
            XCTAssertEqual(verse.translation, "ESV")
            XCTAssertFalse(verse.reference.isEmpty)
            XCTAssertFalse(verse.passage.isEmpty)
            XCTAssertEqual(verse.passage, verse.passage.trimmingCharacters(in: .whitespacesAndNewlines))
            XCTAssertTrue(verse.passage.first?.isUppercase == true, "\(verse.reference) should start a sentence")
            XCTAssertTrue(".!?".contains(verse.passage.last!), "\(verse.reference) should end a sentence")
        }
    }
}
