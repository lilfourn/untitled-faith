import SwiftUI

struct ContributionAmountStep: View {
    @Binding var draft: ContributionDraft
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 64

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Text("How much?")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 16)

                    Spacer(minLength: 28)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("$")
                            .font(.system(size: amountSize * 0.48, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(draft.entry)
                            .font(.system(size: amountSize, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: false))
                            .animation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.12), value: draft.entry)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Contribution amount")
                    .accessibilityValue(draft.amountFormatted)
                    .accessibilityIdentifier("contribution-amount")
                    Spacer(minLength: 28)

                    ContributionNumberPad(onDigit: { draft.insert($0) }, onDelete: { draft.deleteLastDigit() })
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .sensoryFeedback(.selection, trigger: draft.entry)
    }
}
