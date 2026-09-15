import Foundation

/// Searches references and verse words locally. Every selectable result carries its full source text.
struct VerseSearch: Sendable {
    let bible: BibleStore

    func results(for query: String) throws -> [ScriptureCitation] {
        let query = Self.normalize(query)
        if query.isEmpty {
            return ["John 3:16", "Psalm 23:1", "Romans 8:28", "Proverbs 3:5–6"]
                .compactMap(BibleReference.parse).compactMap(citation)
        }
        if let reference = Self.reference(query) {
            guard let selected = citation(reference) else { return [] }
            if reference.verse != nil { return [selected] }
            let verses = try bible.verses(in: reference).prefix(7).map { verseCitation($0) }
            return [selected] + verses
        }
        // A trailing colon means the reader is choosing a verse within this chapter.
        if query.hasSuffix(":"), let chapter = BibleReference.parse(String(query.dropLast())), chapter.verse == nil {
            return try bible.verses(in: chapter).prefix(8).map { verseCitation($0) }
        }
        let books = BibleBook.all.filter { book in
            ([book.name] + book.aliases).contains { BibleBook.normalize($0).hasPrefix(query) }
        }
        if !books.isEmpty {
            return books.prefix(8).compactMap { citation(BibleReference(book: $0, chapter: 1, verse: 1)) }
        }
        return try bible.search(typing: query, limit: 8).map { verseCitation($0) }
    }

    func exactResult(for query: String) -> ScriptureCitation? {
        Self.reference(Self.normalize(query)).flatMap(citation)
    }

    private static func normalize(_ query: String) -> String {
        BibleBook.normalize(query).replacingOccurrences(
            of: #"(?<=[a-z])(?=\d)"#, with: " ", options: .regularExpression)
    }

    private static func reference(_ query: String) -> BibleReference? {
        guard query.range(of: #"^.+?\s+\d{1,3}(?:\s*:\s*\d{1,3})?(?:\s*[-–—]\s*(?:\d{1,3}\s*:\s*)?\d{1,3})?$"#,
                          options: .regularExpression) != nil else { return nil }
        return BibleReference.parse(query)
    }

    private func citation(_ reference: BibleReference) -> ScriptureCitation? {
        guard let verses = try? bible.verses(in: reference), let first = verses.first, let last = verses.last,
              first.reference.idRange.lowerBound == reference.idRange.lowerBound,
              reference.verse == nil || last.reference.idRange.upperBound == reference.idRange.upperBound else { return nil }
        return bible.citation(reference)
    }

    private func verseCitation(_ verse: BibleVerse) -> ScriptureCitation {
        ScriptureCitation(id: UUID(), reference: verse.reference.description,
                          translation: bible.translation.id, passage: verse.text)
    }
}
