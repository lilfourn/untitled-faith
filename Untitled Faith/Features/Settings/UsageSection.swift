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
                    Text("Monthly usage remaining")
                    Spacer()
                    Text("Preview").foregroundStyle(.secondary)
                }
                ProgressView(value: 0, total: 100)
                    .tint(AppTheme.accent)
                    .accessibilityLabel("Monthly usage remaining")
                    .accessibilityValue("Unavailable in preview")
            } else if let usage {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Monthly usage remaining")
                        Spacer()
                        Text("\(usage.remainingPercent)%")
                            .monospacedDigit()
                    }
                    ProgressView(value: Double(usage.remainingPercent), total: 100)
                        .tint(AppTheme.accent)
                        .accessibilityLabel("Monthly usage remaining")
                        .accessibilityValue("\(usage.remainingPercent) percent")
                }
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Free answers today", value: "\(usage.free.remainingToday) of \(usage.free.dailyLimit) left")
                    LabeledContent("Free answers this month", value: "\(usage.free.remainingThisMonth) of \(usage.free.monthlyLimit) left")
                    if usage.free.remainingThisMonth == 0 {
                        resetNotice("Monthly allowance resets", at: usage.resetsAt)
                    } else if usage.free.remainingToday == 0 {
                        resetNotice("Daily allowance resets", at: usage.free.resetsAt)
                    }
                    if usage.usage.pendingRequests > 0 {
                        Text("Pending requests are included until their usage is confirmed.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
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

    @ViewBuilder
    private func resetNotice(_ title: String, at timestamp: String?) -> some View {
        if let timestamp, let date = ISO8601DateFormatter().date(from: timestamp) {
            Text("\(title) \(date.formatted(date: .abbreviated, time: .shortened)).")
                .foregroundStyle(.secondary)
        } else {
            Text("Daily free answers reset at midnight UTC.")
                .foregroundStyle(.secondary)
        }
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
