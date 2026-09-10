import SwiftUI

struct AnswerTextView: View {
    let answer: FaithAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(blocks) { block in
                if let quote = block.quote, let source = answer.sources?.first(where: { $0.id == quote.sourceID }) {
                    QuotationCard(text: quote.text, attribution: quote.attribution, kind: source.kind, sourceURL: source.url)
                } else {
                    AnswerMarkdown(block.text, sources: answer.isComplete ? (answer.sources ?? []) : [])
                }
            }
            if answer.isComplete, let sources = answer.sources, !sources.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sources) { source in
                        Link(destination: source.url) {
                            Label(source.title, systemImage: source.kind == .scripture ? "book" : "text.quote")
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
        }
    }

    private struct Block: Identifiable {
        let id: Int
        let text: String
        var quote: AnswerQuote?
    }

    private var blocks: [Block] {
        guard answer.isComplete else { return [Block(id: 0, text: answer.text)] }
        let text = answer.text as NSString
        var blocks: [Block] = []
        var position = 0
        for quote in answer.quotes ?? [] {
            guard quote.startIndex >= position, quote.endIndex <= text.length, quote.endIndex > quote.startIndex else { continue }
            if quote.startIndex > position {
                blocks.append(Block(id: position, text: text.substring(with: NSRange(location: position, length: quote.startIndex - position))))
            }
            blocks.append(Block(id: quote.startIndex, text: quote.text, quote: quote))
            position = quote.endIndex
        }
        if position < text.length { blocks.append(Block(id: position, text: text.substring(from: position))) }
        return blocks
    }

}
