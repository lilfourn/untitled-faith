import XCTest
@testable import Untitled_Faith

final class AnswerStreamLinesTests: XCTestCase {
    func testFramesOnlyCRAndLFAndPreservesUnicodeAndSplitUTF8() throws {
        var lines = AnswerStreamLines()
        let text = "data: 🙏\u{0085}\u{2028}\u{2029}\r\n\rnext\n"
        let result = try text.utf8.compactMap { try lines.consume($0) }
        XCTAssertEqual(result, ["data: 🙏\u{0085}\u{2028}\u{2029}", "", "next"])
    }

    func testRejectsInvalidUTF8AndBoundsUnterminatedInput() throws {
        var invalid = AnswerStreamLines()
        XCTAssertNil(try invalid.consume(0xff))
        XCTAssertThrowsError(try invalid.consume(10))
        var long = AnswerStreamLines()
        for _ in 0..<(512 * 1024) { XCTAssertNil(try long.consume(65)) }
        XCTAssertThrowsError(try long.consume(65))
    }

    func testUnicodeAnswerSurvivesFullStreamWithCorrelatableRequestID() throws {
        var lines = AnswerStreamLines()
        var parser = AnswerEventParser()
        let id = UUID()
        let text = "Grow in patience\u{2028}🙏"
        let frames: [[String: Any]] = [
            ["type": "start", "requestID": id.uuidString],
            ["type": "delta", "text": text],
            ["type": "done", "answer": ["text": text, "scripture": [], "commentary": []]],
        ]
        var answer: FaithAnswer?
        for frame in frames {
            var bytes = Data("data: ".utf8)
            bytes.append(try JSONSerialization.data(withJSONObject: frame))
            bytes.append(contentsOf: [10, 10])
            for byte in bytes {
                if let line = try lines.consume(byte), !line.isEmpty, let event = try parser.consume(line),
                   case .done(let result) = event { answer = result }
            }
        }
        XCTAssertEqual(answer?.text, text)
        XCTAssertEqual(parser.requestID, id)
    }
}
