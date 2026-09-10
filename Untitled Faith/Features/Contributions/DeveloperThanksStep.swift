import SwiftUI

struct DeveloperThanksStep: View {
    @Binding var draft: ContributionDraft
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var percentageSize = 48
    @ScaledMetric(relativeTo: .largeTitle) private var moneySize = 36

    private var percent: Double { Double(draft.developerShareBasisPoints) / 100 }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Text("Share your thanks?")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 12)
                    DeveloperNoteDisclosure()
                        .padding(.top, 4)
                    Spacer(minLength: 20)

                    Text(percent / 100, format: .percent.precision(.fractionLength(0...1)))
                        .font(.system(size: percentageSize, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: percent))
                        .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.06), value: percent)
                        .accessibilityIdentifier("developer-share-percentage")
                    Slider(value: Binding(
                        get: { percent },
                        set: { draft.developerShareBasisPoints = Int(($0 * 100).rounded()) }
                    ), in: 0...3, step: 0.1)
                    .tint(AppTheme.accent)
                    .accessibilityLabel("Optional developer share")
                    .accessibilityValue(Text(percent / 100, format: .percent.precision(.fractionLength(0...1))))
                    .accessibilityIdentifier("developer-share-slider")
                    .padding(.top, 24)
                    HStack {
                        Text("0%")
                        Spacer()
                        Text("3%")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    Spacer(minLength: 24)

                    VStack(spacing: 8) {
                        Text("Developer share")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(ContributionSelection.money(draft.selection.developerCents))
                            .font(.system(size: moneySize, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(draft.selection.developerCents)))
                            .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.08), value: draft.selection.developerCents)
                            .accessibilityIdentifier("developer-share-amount")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 520)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .sensoryFeedback(.selection, trigger: draft.developerShareBasisPoints)
    }
}
