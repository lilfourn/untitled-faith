import SwiftUI

struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        switch message {
        case .question(_, let text):
            HStack {
                Spacer(minLength: 32)
                Text(text)
                    .padding(16)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                    .textSelection(.enabled)
            }
        case .answer(_, let answer):
            VStack(alignment: .leading, spacing: 16) {
                AnswerTextView(answer: answer)
                if !answer.isComplete {
                    Text("Answer interrupted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(answer.scripture) { citation in
                    QuotationCard(text: citation.passage, attribution: "\(citation.reference) · \(citation.translation)", kind: .scripture)
                }
                if !answer.commentary.isEmpty {
                    Text("COMMENTARY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(answer.commentary) { citation in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(citation.excerpt)
                            Text([citation.author, citation.organization].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Link(citation.title, destination: citation.sourceURL)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
