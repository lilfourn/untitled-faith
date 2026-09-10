import SwiftUI

struct ContributionWizard: View {
    var checkout: any ContributionCheckout = UnconfiguredContributionCheckout()
    var usesBrowserCheckout = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ContributionDraft()
    @State private var step = 0
    @State private var movingForward = true
    @State private var isContinuing = false
    @State private var checkoutError: String?

    var body: some View {
        VStack(spacing: 0) {
            navigation
            ZStack {
                if step == 0 { ContributionAmountStep(draft: $draft).transition(stepTransition) }
                else { DeveloperThanksStep(draft: $draft).transition(stepTransition) }
            }
            .clipped()
        }
        .foregroundStyle(AppTheme.accent)
        .background(AppTheme.background)
        #if DEBUG
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--contribution-preview-dark") ? .dark : nil)
        #endif
        .safeAreaInset(edge: .bottom) { continueButton }
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.04), value: step)
        .alert("Contributions", isPresented: Binding(get: { checkoutError != nil }, set: { if !$0 { checkoutError = nil } })) {
            Button("OK", role: .cancel) { checkoutError = nil }
        } message: { Text(checkoutError ?? "") }
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
                           removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity))
    }

    private var navigation: some View {
        HStack {
            Button {
                movingForward = false
                step = 0
            } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.medium)).frame(width: 44, height: 44)
            }
            .opacity(step == 0 ? 0 : 1)
            .disabled(step == 0 || isContinuing)
            .accessibilityHidden(step == 0)
            .accessibilityLabel("Back to contribution amount")
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.footnote.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close contribution")
            .disabled(isContinuing)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var continueButton: some View {
        VStack(spacing: 12) {
            Button {
                if step == 0 {
                    movingForward = true
                    step = 1
                } else {
                    Task {
                        isContinuing = true
                        defer { isContinuing = false }
                        do {
                            try await checkout.begin(draft.selection)
                            if usesBrowserCheckout { dismiss() }
                        }
                        catch { checkoutError = error.localizedDescription }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if isContinuing { ProgressView().tint(AppTheme.background) }
                    Text(step == 0 ? "Next" : "Continue · \(draft.amountFormatted)")
                        .font(.subheadline.weight(.semibold))
                    if step == 0 { Image(systemName: "arrow.right").font(.subheadline.weight(.semibold)) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(AppTheme.background)
                .background(AppTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!draft.canContinue || isContinuing)
            .opacity(draft.canContinue ? 1 : 0.3)
            .accessibilityIdentifier("contribution-continue")
            .accessibilityLabel(step == 0 ? "Next" : "Continue with \(draft.amountFormatted)")
            if step == 0 && draft.amountCents > 0 && !draft.canContinue {
                Text("Minimum $1").font(.caption).foregroundStyle(.secondary)
            }
            if step == 1 && usesBrowserCheckout {
                Text("Continue opens secure checkout in your browser. Apple Pay is available on supported devices. Usage funding is credited after payment fees and your selected share; fees may be adjusted after settlement.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(AppTheme.background)
    }
}

#Preview { ContributionWizard() }
