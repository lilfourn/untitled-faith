import AuthenticationServices
import SwiftUI

struct AppleSignInControl: View {
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void
    @State private var authorization = AppleAuthorizationPresenter()
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var preferredTextSize = 18.0
    @ScaledMetric(relativeTo: .body) private var preferredLogoSize = 20.0

    private var title: String { String(localized: "Continue with Apple") }
    private var background: Color { colorScheme == .dark ? .white : .black }
    private var foreground: Color { colorScheme == .dark ? .black : .white }

    var body: some View {
        Button {
            authorization.begin(onRequest: onRequest, onCompletion: onCompletion)
        } label: {
            GeometryReader { geometry in
                let font = fittedFont(for: geometry.size.width)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "apple.logo")
                        // Font sizing preserves the symbol's native baseline metrics.
                        .font(.system(size: preferredLogoSize, weight: .regular))

                    Text(title)
                        .font(Font(font))
                        .fixedSize()
                }
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: max(56, preferredLogoSize + 28))
            .background(background, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .background(AppleAuthorizationWindow(presenter: authorization).allowsHitTesting(false))
        .compositingGroup()
    }

    private func fittedFont(for width: CGFloat) -> UIFont {
        let font = UIFont.systemFont(ofSize: preferredTextSize, weight: .medium)
        let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
        let availableTextWidth = max(1, width - 40 - preferredLogoSize - 8)
        let scale = min(1, availableTextWidth / textWidth)
        return UIFont.systemFont(ofSize: preferredTextSize * scale, weight: .medium)
    }
}
