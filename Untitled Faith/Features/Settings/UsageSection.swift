import SwiftUI

struct UsageSection: View {
    let session: AppSession
    var addUsage: () -> Void = {}
    @State private var usage: AccountUsage?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if session.isPreview {
                HStack {
                    Text("Usage remaining")
                    Spacer()
                    Text("Preview").foregroundStyle(.secondary)
                }
                ProgressView(value: 0, total: 100)
                    .tint(AppTheme.accent)
                    .accessibilityLabel("Usage remaining")
                    .accessibilityValue("Unavailable in preview")
            } else if let usage {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Usage remaining")
                        Spacer()
                        Text("\(usage.remainingPercent)%")
                            .monospacedDigit()
                    }
                    ProgressView(value: Double(usage.remainingPercent), total: 100)
                        .tint(AppTheme.accent)
                        .accessibilityLabel("Usage remaining")
                        .accessibilityValue("\(usage.remainingPercent) percent")
                }
            }
            if let error {
                Text(error).foregroundStyle(.secondary)
                Button("Try again") { Task { await refresh() } }.disabled(isLoading)
            }
            if isLoading && usage == nil { ProgressView("Usage remaining") }
            Divider()
            Button("Add usage", systemImage: "plus", action: addUsage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 32)
        }
        .padding(24)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .task { if session.isSignedIn { await refresh() } }
    }

    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { usage = try await session.loadUsage() }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }
}
