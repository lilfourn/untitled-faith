import SwiftUI

struct QuotationPreview {
    static let characterLimit = 200
    let text: String
    let isTruncated: Bool

    init(_ fullText: String) {
        isTruncated = fullText.count > Self.characterLimit
        text = isTruncated
            ? String(fullText.prefix(Self.characterLimit - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            : fullText
    }
}

struct QuotationCard: View {
    let text: String
    let attribution: String
    let kind: AnswerSource.Kind
    var sourceURL: URL?
    @State private var showingFullQuote = false

    private var preview: QuotationPreview { QuotationPreview(text) }
    private var quoteFont: Font { kind == .scripture ? .system(.body, design: .serif) : .body.italic() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.text)
                .font(quoteFont)
                .textSelection(.enabled)
            Text(attribution)
                .font(.caption)
                .foregroundStyle(.secondary)
            if preview.isTruncated {
                Button("Read more") { showingFullQuote = true }
                    .font(.subheadline.weight(.medium))
                    .padding(.top, 4)
                    .accessibilityHint("Opens the full quotation")
                    .accessibilityIdentifier("quote-read-more")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showingFullQuote) {
            ExpandedQuotation(text: text, attribution: attribution, kind: kind, sourceURL: sourceURL)
        }
    }
}

struct ExpandedQuotation: View {
    let text: String
    let attribution: String
    let kind: AnswerSource.Kind
    var sourceURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(attribution)
                        .font(.headline)
                    Text(text)
                        .font(kind == .scripture ? .system(.body, design: .serif) : .body.italic())
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("expanded-quotation-text")
                    if let sourceURL {
                        Link("View source", destination: sourceURL)
                            .font(.subheadline)
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppTheme.background)
            .navigationTitle(kind == .scripture ? "Scripture" : "Commentary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
