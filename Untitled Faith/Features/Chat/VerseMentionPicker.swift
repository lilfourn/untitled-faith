import SwiftUI

struct VerseMentionPicker: View {
    let query: String
    let select: (ScriptureCitation) -> Void
    let dismiss: () -> Void
    @State private var results: [ScriptureCitation] = []
    @State private var loadedQuery: String?
    @State private var error: String?
    @ScaledMetric private var rowHeight = 52.0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Scripture")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Close verse search", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .frame(width: 44, height: 32)
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 12)

            if loadedQuery != query {
                ProgressView("Searching verses…").font(.caption).padding(12)
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.secondary).padding(12)
            } else if results.isEmpty {
                Text("No verses found. Try John 3:16 or words from a verse.")
                    .font(.caption).foregroundStyle(.secondary).padding(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { citation in
                            Button { select(citation) } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(citation.reference) · \(citation.translation)")
                                            .font(.subheadline.weight(.medium)).lineLimit(1)
                                        Text(citation.passage)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "plus").font(.caption.weight(.semibold))
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: rowHeight)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Attach \(citation.reference), \(citation.translation)")
                            .accessibilityHint(citation.passage)
                        }
                    }
                }
                .frame(height: min(Double(results.count), 3) * rowHeight)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(.bottom, 6)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .accessibilityIdentifier("verse-mention-picker")
        .task(id: query) {
            let requested = query
            do {
                try await Task.sleep(for: .milliseconds(120))
                guard let bible = BibleStore.bundled else {
                    error = "Bible search is unavailable. Try reopening the app."
                    loadedQuery = requested
                    return
                }
                let found = try await Task.detached(priority: .userInitiated) {
                    try VerseSearch(bible: bible).results(for: requested)
                }.value
                try Task.checkCancellation()
                results = found
                error = nil
                loadedQuery = requested
            } catch is CancellationError {
                // A newer query owns the list now.
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Couldn’t search the Bible. Try a different reference."
                loadedQuery = requested
            }
        }
    }
}
