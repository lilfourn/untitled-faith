import SwiftUI

struct OwnerPaymentsView: View {
    let api: PaymentAPI
    @State private var summary: OwnerPaymentSummary?
    @State private var error: String?

    var body: some View {
        List {
            if let summary {
                Section("Allocated funds") {
                    moneyRow("Users’ usage funding", summary.stripe.usageFundingMicros + summary.legacy.usageFundingMicros)
                    moneyRow("Your developer share", summary.stripe.developerShareMicros + summary.legacy.developerShareMicros)
                    Text("Your share is separate from spendable usage. These are accounting allocations, not bank payouts.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Stripe payments") {
                    moneyRow("Payments received", summary.stripe.grossMicros)
                    moneyRow("Refunds", summary.stripe.refundedMicros)
                    moneyRow("Confirmed processing fees", summary.stripe.confirmedFeeMicros)
                    moneyRow("Estimated processing fees", summary.stripe.estimatedFeeMicros)
                    moneyRow("Disputed payments", summary.stripe.disputedMicros)
                    LabeledContent("Awaiting final fees", value: "\(summary.stripe.awaitingFees)")
                    Text("Stripe pays the combined proceeds to your bank. Keep users’ unused funding reserved. Refund and dispute fees can create additional business expenses.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Users’ balances") {
                    moneyRow("Balance remaining", summary.users.userBalanceMicros)
                    moneyRow("Reserved for active requests", summary.users.userReservedMicros)
                }
                Section("Monthly allocations, UTC") {
                    ForEach(summary.months) { month in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(month.month).font(.headline)
                            moneyRow("Usage", month.usageFundingMicros)
                            moneyRow("Your share", month.developerShareMicros)
                        }
                    }
                }
                Section("Reconciliation") {
                    LabeledContent("Pending payment updates", value: "\(summary.operations.pendingEvents)")
                    LabeledContent("Open checkouts", value: "\(summary.operations.pendingCheckouts)")
                }
            } else if error == nil { ProgressView("Loading payments…") }
            if let error {
                Text(error).foregroundStyle(.secondary)
                Button("Try again") { Task { await load() } }
            }
        }
        .navigationTitle("Payment overview")
        .task { await load() }
        .refreshable { await load() }
    }

    private func moneyRow(_ label: String, _ amount: Int64) -> some View {
        LabeledContent(label, value: PaymentEntry.money(amount))
    }

    private func load() async {
        error = nil
        do { summary = try await api.ownerSummary() }
        catch { self.error = error.localizedDescription }
    }
}
