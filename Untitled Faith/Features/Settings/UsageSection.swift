import SwiftUI

struct UsageSection: View {
    let session: AppSession
    var addUsage: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Usage remaining")
                    Spacer()
                    Text(session.isPreview ? "Preview" : session.accountUsage.value.map { "\($0.remainingPercent)%" } ?? "—")
                        .monospacedDigit()
                }
                ProgressView(value: Double(session.accountUsage.value?.remainingPercent ?? 0), total: 100)
                    .tint(AppTheme.accent)
                    .opacity(session.accountUsage.value == nil ? 0.35 : 1)
                    .accessibilityLabel("Usage remaining")
                    .accessibilityValue(session.accountUsage.value.map { "\($0.remainingPercent) percent" } ?? "Not available yet")
            }
            if session.accountUsage.value == nil, let error = session.accountUsage.errorMessage {
                Text(error).foregroundStyle(.secondary)
                Button("Try again") { session.refreshUsage(force: true) }
            }
            Divider()
            Button("Add usage", systemImage: "plus", action: addUsage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 32)
        }
        .padding(24)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .task { session.refreshUsage() }
    }
}
