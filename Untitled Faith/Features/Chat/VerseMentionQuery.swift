import Foundation

/// Only the @ query at the insertion point is replaced; surrounding prose stays intact.
struct VerseMentionQuery: Equatable {
    let range: NSRange
    let text: String

    static func active(in draft: String, selection: NSRange) -> Self? {
        guard selection.length == 0, selection.location >= 0, selection.location <= draft.utf16.count,
              let caret = Range(selection, in: draft)?.lowerBound,
              let at = draft[..<caret].lastIndex(of: "@") else { return nil }
        if at != draft.startIndex {
            let previous = draft[draft.index(before: at)]
            guard previous.isWhitespace || "([{\"“‘".contains(previous) else { return nil }
        }
        let query = String(draft[draft.index(after: at)..<caret])
        guard query.count <= 80, !query.contains(where: { $0.isNewline || $0 == "@" }) else { return nil }
        // Once prose follows a complete reference, leave the caret free for the question.
        let fragment = String(draft[at..<caret])
        if let match = referencePattern.firstMatch(in: fragment, range: NSRange(fragment.startIndex..., in: fragment)),
           let matched = Range(match.range, in: fragment),
           !fragment[matched.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        return Self(range: NSRange(at..<caret, in: draft), text: query)
    }

    /// Also resolve complete typed/pasted @references when Send is pressed after the keyboard closes.
    static func references(in draft: String) -> [BibleReference] {
        referencePattern.matches(in: draft, range: NSRange(draft.startIndex..., in: draft)).compactMap { match in
            func group(_ index: Int) -> String? {
                Range(match.range(at: index), in: draft).map { String(draft[$0]) }
            }
            guard let name = group(1), let book = BibleBook.named(name), let chapter = group(2).flatMap(Int.init) else { return nil }
            return BibleReference.make(book: book, chapter: chapter, verse: group(3).flatMap(Int.init),
                                       endChapter: group(4).flatMap(Int.init), endVerse: group(5).flatMap(Int.init))
        }
    }

    func inserting(_ reference: String, in draft: String) -> (text: String, selection: NSRange)? {
        guard let span = Range(range, in: draft), draft[span] == "@" + text else { return nil }
        let suffix = draft[span.upperBound...]
        let separator = suffix.first.map { $0.isWhitespace || ",.;:!?)]}".contains($0) } == true ? "" : " "
        let replacement = reference + separator
        return (draft.replacingCharacters(in: span, with: replacement),
                NSRange(location: range.location + replacement.utf16.count, length: 0))
    }

    private static let referencePattern: NSRegularExpression = {
        let names = BibleBook.all.flatMap { [$0.name] + $0.aliases }
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: #"\s*"#) }
            .joined(separator: "|")
        return try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}._%+\-])@("# + names +
            #")\.?\s*(\d{1,3})(?:\s*:\s*(\d{1,3}))?(?:\s*[-–—]\s*(?:(\d{1,3})\s*:\s*)?(\d{1,3}))?(?![\p{L}\d:–—-])"#,
            options: [.caseInsensitive])
    }()
}
