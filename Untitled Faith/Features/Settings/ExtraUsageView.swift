import SwiftUI

struct ExtraUsageView: View {
    let funding: AccountUsage.Funding

    private var balance: String {
        (Decimal(funding.availableMicros) / 1_000_000).formatted(.currency(code: "USD"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Extra usage")
                Spacer()
                Text(balance).monospacedDigit()
            }
            ProgressView(value: Double(funding.availableMicros), total: Double(max(1, funding.displayTotalMicros)))
                .tint(AppTheme.accent)
                .accessibilityLabel("Extra usage")
                .accessibilityValue("\(balance) remaining")
        }
    }
}
