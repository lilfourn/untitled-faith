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
            if let error = session.accountUsage.errorMessage {
                if let updatedAt = session.accountUsage.updatedAt {
                    Text("Last updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("Try again") { session.refreshUsage(force: true) }
            }
            if (session.accountUsage.value?.usage.requestsNeedingReview ?? 0) > 0 {
                Text("Some interrupted requests need review before their reserved usage can be resolved.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("Contact support", destination: URL(string: "mailto:untitledfaith@gmail.com")!)
            }
            Divider()
            PaymentEntry(session: session, addUsage: addUsage)
        }
        .padding(24)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .task { session.refreshUsage() }
    }
}
