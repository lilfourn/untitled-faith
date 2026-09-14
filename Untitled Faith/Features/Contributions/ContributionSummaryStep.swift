import SwiftUI

struct ContributionSummaryStep: View {
    let selection: ContributionSelection
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 48

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Text("Payment summary")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 12)

                    Spacer(minLength: 28)
                    VStack(spacing: 8) {
                        Text("Estimated usage credit")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(ContributionSelection.money(selection.estimatedUsageCents))
                            .font(.system(size: amountSize, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .accessibilityIdentifier("contribution-estimated-usage")
                        Text("For your AI answers. Each answer’s cost varies.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer(minLength: 28)

                    VStack(spacing: 16) {
                        LabeledContent("You pay", value: ContributionSelection.money(selection.amountCents))
                            .fontWeight(.semibold)
                        LabeledContent {
                            Text("−\(ContributionSelection.money(selection.developerCents))")
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Developer share")
                                Text(Double(selection.developerShareBasisPoints) / 10_000,
                                     format: .percent.precision(.fractionLength(0...1)))
                                    .font(.caption)
                            }
                        }
                        LabeledContent("Estimated Stripe fee", value: "−\(ContributionSelection.money(selection.estimatedFeeCents))")
                        Divider()
                        LabeledContent("Estimated usage credit", value: ContributionSelection.money(selection.estimatedUsageCents))
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                    .labeledContentStyle(.automatic)
                    .accessibilityIdentifier("contribution-payment-summary")

                    Text("Your developer share and payment fee come out of the total. Your usage credit may be adjusted once Stripe confirms the final fee.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 520)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }
}

#Preview {
    ContributionSummaryStep(selection: ContributionSelection(amountCents: 1_000, developerShareBasisPoints: 300))
        .foregroundStyle(AppTheme.accent)
        .background(AppTheme.background)
}
