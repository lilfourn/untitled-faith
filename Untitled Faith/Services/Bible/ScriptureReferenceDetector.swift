import Foundation

/// Finds scripture references written in prose, such as an AI answer that mentions "Rom. 8:28–30".
enum ScriptureReferenceDetector {
    /// References in order of first appearance, without duplicates.
    static func references(in text: String) -> [BibleReference] {
        var seen: Set<BibleReference> = []
        var found: [BibleReference] = []
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            func group(_ index: Int) -> String? {
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : String(text[Range(range, in: text)!])
            }
            guard let bookText = group(1), let book = BibleBook.named(bookText),
                  let chapter = group(2).flatMap({ Int($0) }),
                  let reference = BibleReference.make(book: book, chapter: chapter, verse: group(3).flatMap { Int($0) },
                                                      endChapter: group(4).flatMap { Int($0) }, endVerse: group(5).flatMap { Int($0) }),
                  seen.insert(reference).inserted else { continue }
            found.append(reference)
        }
        return found
    }

    /// Full names plus abbreviations long enough not to collide with ordinary words ("is", "am", "so").
    private static let pattern: NSRegularExpression = {
        let names = BibleBook.all.flatMap { book in
            [book.name] + book.aliases.filter { alias in
                alias.first?.isNumber == true || alias.hasPrefix("i") && alias.contains(" ") || alias.count >= 3
            }
        }
        let alternatives = names.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: #"\s+"#) }
            .joined(separator: "|")
        let pattern = #"(?<![A-Za-z])("# + alternatives + #")\.?\s+(\d{1,3})(?:\s*:\s*(\d{1,3}))?(?:\s*[-–—]\s*(?:(\d{1,3})\s*:\s*)?(\d{1,3}))?(?![:\d])"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()
}
