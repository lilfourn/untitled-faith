import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Bindable var session: AppSession
    @State private var legalDocument: LegalDocument?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                signInCard
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(AppTheme.background)
        .sheet(item: $legalDocument) { document in
            LegalDocumentView(document: document)
        }
        .alert("Sign in", isPresented: Binding(
            get: { session.signInError != nil },
            set: { if !$0 { session.signInError = nil } }
        )) {
            Button("OK", role: .cancel) { session.signInError = nil }
        } message: {
            Text(session.signInError ?? "")
        }
    }

    private var signInCard: some View {
        VStack(spacing: 36) {
            Color.primary
                .frame(maxWidth: 260)
                .frame(height: 56)
                .mask {
                    // The Gridbloom export has black lettering on a square white canvas.
                    // Mask with its lettering so it follows the system appearance.
                    Image("Wordmark")
                        .resizable()
                        .scaledToFill()
                        .colorInvert()
                        .luminanceToAlpha()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Untitled Faith")
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 18) {
                AppleSignInControl(onRequest: session.prepareAppleAuthorization, onCompletion: session.handleAppleAuthorization)
                    .disabled(!session.canSignIn)
                    .opacity(session.isSigningIn || session.isRestoring ? 0.5 : 1)

                Text("By continuing, you agree to our [Terms of Use](untitledfaith://terms).\nRead our [Privacy Policy](untitledfaith://privacy).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .tint(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        guard let document = LegalDocument(link: url) else { return .systemAction }
                        legalDocument = document
                        return .handled
                    })
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 44)
        .frame(maxWidth: 360)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(.primary.opacity(0.04), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 24, y: 10)
    }
}
