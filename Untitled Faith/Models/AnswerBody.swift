import Foundation

/// Places fetched Scripture beside its first prose reference without changing saved text or quote offsets.
enum AnswerBody {
    struct Block: Identifiable {
        let id: String
        let text: String
        var quote: AnswerQuote?
        var scripture: ScriptureCitation?
    }

    static func blocks(for answer: FaithAnswer) -> [Block] {
        guard answer.isComplete else { return [Block(id: "text-0", text: answer.text)] }
        let text = answer.text as NSString
        var blocks: [Block] = []
        var remaining = AnswerScripture.supplementalCards(in: answer)
        var position = 0

        func appendProse(_ prose: String, offset: Int) {
            var pending = ""
            var start = offset
            for paragraph in paragraphs(in: prose) {
                pending += paragraph
                let references = ScriptureReferenceDetector.references(in: paragraph)
                let cards = remaining.filter { citation in
                    guard let passage = BibleReference.parse(citation.reference) else { return false }
                    return references.contains { AnswerScripture.contains(passage, $0) }
                }
                guard !cards.isEmpty else { continue }
                blocks.append(Block(id: "text-\(start)", text: pending))
                start += pending.utf16.count
                pending = ""
                for citation in cards {
                    blocks.append(Block(id: "scripture-\(citation.id)", text: citation.passage, scripture: citation))
                }
                let added = Set(cards.map(\.id))
                remaining.removeAll { added.contains($0.id) }
            }
            if !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(Block(id: "text-\(start)", text: pending))
            }
        }

        for quote in answer.quotes ?? [] {
            guard quote.startIndex >= position, quote.endIndex <= text.length, quote.endIndex > quote.startIndex else { continue }
            if quote.startIndex > position {
                appendProse(text.substring(with: NSRange(location: position, length: quote.startIndex - position)), offset: position)
            }
            blocks.append(Block(id: "quote-\(quote.id)", text: quote.text, quote: quote))
            position = quote.endIndex
        }
        if position < text.length { appendProse(text.substring(from: position), offset: position) }
        // Preserve legacy cards whose reference is absent from the saved prose.
        blocks += remaining.map { Block(id: "scripture-\($0.id)", text: $0.passage, scripture: $0) }
        return blocks
    }

    private static func paragraphs(in text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var paragraph = ""
        var fence: (marker: Character, count: Int)?
        for (index, line) in lines.enumerated() {
            paragraph += line + (index < lines.count - 1 ? "\n" : "")
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let marker = trimmed.first, marker == "`" || marker == "~" {
                let length = trimmed.prefix(while: { $0 == marker }).count
                if let open = fence {
                    if marker == open.marker, length >= open.count,
                       trimmed.dropFirst(length).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                } else if length >= 3 { fence = (marker, length) }
            }
            guard trimmed.isEmpty, fence == nil else { continue }
            // Keep loose/nested lists together so inserting a card cannot reset list structure.
            let next = lines.dropFirst(index + 1).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            if next.range(of: #"^(?:[ \t]+|(?:[-+*]|\d+[.)])\s)"#, options: .regularExpression) != nil { continue }
            result.append(paragraph)
            paragraph = ""
        }
        if !paragraph.isEmpty { result.append(paragraph) }
        return result
    }
}
