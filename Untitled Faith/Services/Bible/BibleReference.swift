import Foundation

/// A verse, verse range, or whole chapter, e.g. "John 3:16", "Proverbs 3:5–6", "Psalm 23", "Genesis 1:1–2:3".
struct BibleReference: Hashable, Sendable, CustomStringConvertible {
    let book: BibleBook
    let chapter: Int
    /// `nil` means the whole chapter.
    let verse: Int?
    /// Set only when a range ends in a later chapter.
    let endChapter: Int?
    let endVerse: Int?

    init(book: BibleBook, chapter: Int, verse: Int? = nil, endChapter: Int? = nil, endVerse: Int? = nil) {
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.endChapter = endChapter
        self.endVerse = endVerse
    }

    /// Canonical display form using an en dash for ranges.
    var description: String {
        var text = "\(book.name) \(chapter)"
        guard let verse else { return text }
        text += ":\(verse)"
        if let endChapter, endChapter != chapter, let endVerse {
            text += "–\(endChapter):\(endVerse)"
        } else if let endVerse, endVerse != verse {
            text += "–\(endVerse)"
        }
        return text
    }

    /// Inclusive bounds in the bundled database's verse id scheme (book·1,000,000 + chapter·1,000 + verse).
    var idRange: ClosedRange<Int> {
        let start = Self.id(book: book, chapter: chapter, verse: verse ?? 1)
        if let endChapter, let endVerse { return start...Self.id(book: book, chapter: endChapter, verse: endVerse) }
        if let endVerse { return start...Self.id(book: book, chapter: chapter, verse: endVerse) }
        if verse == nil { return start...Self.id(book: book, chapter: chapter, verse: 999) }
        return start...start
    }

    static func id(book: BibleBook, chapter: Int, verse: Int) -> Int {
        book.id * 1_000_000 + chapter * 1_000 + verse
    }

    static func from(id: Int) -> BibleReference? {
        let bookID = id / 1_000_000
        guard bookID >= 1, bookID <= BibleBook.all.count else { return nil }
        return BibleReference(book: BibleBook.all[bookID - 1], chapter: (id / 1_000) % 1_000, verse: id % 1_000)
    }

    /// Accepts common forms: "jn. 3:16-18", "1 John 4:19", "Psalm 23", "Gen 1:1–2:3", with an optional
    /// trailing translation label such as "(ESV)".
    static func parse(_ text: String) -> BibleReference? {
        guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : String(text[Range(range, in: text)!])
        }
        guard let bookText = group(1), let book = BibleBook.named(bookText),
              let chapter = group(2).flatMap({ Int($0) }) else { return nil }
        return make(book: book, chapter: chapter, verse: group(3).flatMap { Int($0) },
                    endChapter: group(4).flatMap { Int($0) }, endVerse: group(5).flatMap { Int($0) })
    }

    /// Validates the numbers and normalizes same-chapter ranges.
    static func make(book: BibleBook, chapter: Int, verse: Int?, endChapter: Int?, endVerse: Int?) -> BibleReference? {
        guard chapter >= 1, verse.map({ $0 >= 1 }) ?? true else { return nil }
        guard let verse, let endVerse else {
            return endVerse == nil && endChapter == nil ? BibleReference(book: book, chapter: chapter, verse: verse) : nil
        }
        if let endChapter, endChapter != chapter {
            guard endChapter > chapter, endVerse >= 1 else { return nil }
            return BibleReference(book: book, chapter: chapter, verse: verse, endChapter: endChapter, endVerse: endVerse)
        }
        guard endVerse >= verse else { return nil }
        return BibleReference(book: book, chapter: chapter, verse: verse, endVerse: endVerse == verse ? nil : endVerse)
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*(.+?)\.?\s+(\d{1,3})(?:\s*:\s*(\d{1,3}))?(?:\s*[-–—]\s*(?:(\d{1,3})\s*:\s*)?(\d{1,3}))?\s*(?:\(?[A-Za-z]{2,6}\)?)?\s*$"#
    )
}
