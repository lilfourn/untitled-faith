import SwiftUI

/// Compact references open the exact text that will accompany (or accompanied) the question.
struct ScriptureAttachments: View {
    let citations: [ScriptureCitation]
    var remove: ((UUID) -> Void)? = nil
    @State private var preview: ScriptureCitation?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(citations) { citation in
                    HStack(spacing: 0) {
                        Button { preview = citation } label: {
                            Text("\(citation.reference) · \(citation.translation)")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                        }
                        .accessibilityLabel("View attached passage: \(citation.reference), \(citation.translation)")
                        if let remove {
                            Button { remove(citation.id) } label: {
                                Image(systemName: "xmark").font(.caption)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Remove \(citation.reference)")
                        }
                    }
                    .buttonStyle(.plain)
                    .background(AppTheme.accent.opacity(0.08), in: Capsule())
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .sheet(item: $preview) { citation in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(citation.translation).font(.subheadline).foregroundStyle(.secondary)
                        Text(citation.passage).textSelection(.enabled)
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
                .background(AppTheme.background)
                .navigationTitle(citation.reference)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { preview = nil }
                    }
                }
            }
        }
    }
}
