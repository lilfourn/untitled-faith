import SwiftUI

struct PaymentInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Gridbloom")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                Text("Gridbloom is the LLC behind Untitled Faith.")

                Text("All payments for Untitled Faith are invoiced under Gridbloom. You’ll see Gridbloom on your payment receipts.")
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 24))
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AppTheme.background)
        .navigationTitle("Payment info")
        .navigationBarTitleDisplayMode(.inline)
    }
}
