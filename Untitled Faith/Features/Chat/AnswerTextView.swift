import SwiftUI

struct AnswerTextView: View {
    let answer: FaithAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(AnswerBody.blocks(for: answer)) { block in
                if let quote = block.quote, let source = answer.sources?.first(where: { $0.id == quote.sourceID }) {
                    QuotationCard(text: quote.text, attribution: quote.attribution, kind: source.kind, sourceURL: source.url)
                } else if let citation = block.scripture {
                    QuotationCard(text: citation.passage, attribution: "\(citation.reference) · \(citation.translation)", kind: .scripture)
                } else {
                    AnswerMarkdown(block.text, sources: answer.isComplete ? (answer.sources ?? []) : [])
                }
            }
            if answer.isComplete, let sources = answer.sources, !sources.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(AnswerSourceList.unique(sources, quotes: answer.quotes ?? [])) { source in
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

}
