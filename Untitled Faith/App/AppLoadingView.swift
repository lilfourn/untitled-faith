import SwiftUI

/// Shows the opening verse while the saved session and first screen are prepared.
struct AppLoadingView: View {
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    Text("An intelligent heart acquires knowledge, and the ear of the wise seeks knowledge.")
                        .font(.system(.title2, design: .serif))
                        .lineSpacing(6)
                        .foregroundStyle(.primary)

                    Text("Proverbs 18:15 (ESV)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                .accessibilityElement(children: .combine)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .background(AppTheme.background.ignoresSafeArea())
    }
}
