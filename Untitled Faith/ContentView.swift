import AuthenticationServices
import SwiftUI

struct ContentView: View {
    @State private var session = AppSession()
    @State private var didResolveLaunch = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !didResolveLaunch {
                AppLoadingView()
            } else if session.isPreview || session.isSignedIn {
                ChatHomeView(session: session)
                    .id(session.authentication?.appleUserID ?? "preview")
            } else {
                SignInView(session: session)
            }
        }
        .tint(AppTheme.accent)
        .onOpenURL { url in
            guard (url.scheme == "untitledfaith" && url.host == "payments") ||
                  (url.scheme == "https" && url.host == "untitled-faith-proxy.vendors-c0f.workers.dev" && url.path == "/payments/open") else { return }
            Task {
                await session.becameActive()
                if let api = session.makePaymentAPI() { _ = try? await api.pending() }
                session.refreshUsage(force: true)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await session.becameActive()
            guard !Task.isCancelled else { return }
            didResolveLaunch = true
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
                guard !Task.isCancelled else { return }
                session.refreshUsage()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            session.handleCredentialRevocation()
        }
    }
}

#Preview {
    ContentView()
}
