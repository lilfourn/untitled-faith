import XCTest
@testable import Untitled_Faith

final class ContributionTests: XCTestCase {
    func testAmountEntryHandlesDecimalsDeletionAndBounds() {
        var draft = ContributionDraft()
        XCTAssertFalse(draft.canContinue)
        for key in ["1", "2", ".", "3", "4"] { XCTAssertTrue(draft.insert(key)) }
        XCTAssertEqual(draft.amountCents, 1234)
        XCTAssertFalse(draft.insert("5"))
        XCTAssertFalse(draft.insert("."))
        draft.deleteLastDigit()
        XCTAssertEqual(draft.entry, "12.3")
        XCTAssertEqual(draft.amountCents, 1230)
        draft.deleteLastDigit()
        draft.deleteLastDigit()
        XCTAssertEqual(draft.entry, "12")
        XCTAssertEqual(draft.amountCents, 1200)
        for _ in 0..<8 { draft.deleteLastDigit() }
        XCTAssertEqual(draft.entry, "0")
        for key in ["1", "0", "0", "0"] { draft.insert(key) }
        XCTAssertEqual(draft.amountCents, 100_000)
        XCTAssertFalse(draft.insert("1"))
        XCTAssertEqual(draft.amountCents, 100_000)
    }

    func testOptionalThanksDefaultsToZeroAndDoesNotIncreaseTotal() {
        var draft = ContributionDraft()
        draft.insert("1")
        draft.insert("0")
        XCTAssertEqual(draft.selection.developerCents, 0)
        XCTAssertEqual(draft.selection.usageBeforeFeesCents, 1000)
        draft.developerShareBasisPoints = 300
        XCTAssertEqual(draft.selection.amountCents, 1000)
        XCTAssertEqual(draft.selection.developerCents, 30)
        XCTAssertEqual(draft.selection.usageBeforeFeesCents, 970)
    }

    func testSplitRoundsToCentsAndRemainsConsistentAfterAmountChanges() {
        var draft = ContributionDraft()
        for key in ["1", "2", ".", "3", "4"] { draft.insert(key) }
        draft.developerShareBasisPoints = 300
        XCTAssertEqual(draft.selection.developerCents, 37)
        XCTAssertEqual(draft.selection.developerCents + draft.selection.usageBeforeFeesCents, draft.amountCents)
        draft.deleteLastDigit()
        XCTAssertEqual(draft.selection.amountCents, 1230)
        XCTAssertEqual(draft.selection.developerCents, 37)
        draft.developerShareBasisPoints = 150
        XCTAssertEqual(draft.selection.developerCents, 18)
    }

    func testAmountEntryDoesNotAllowLeadingZeroesOrSubDollarContinuation() {
        var draft = ContributionDraft()
        XCTAssertFalse(draft.insert("0"))
        draft.insert(".")
        draft.insert("5")
        XCTAssertEqual(draft.amountCents, 50)
        XCTAssertFalse(draft.canContinue)
        XCTAssertFalse(draft.insert("-"))
    }
}
