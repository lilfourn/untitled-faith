import AuthenticationServices
import SwiftUI

struct ContentView: View {
    @State private var session = AppSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if session.isPreview || session.isSignedIn {
                ChatView(session: session, service: session.makeAnswerService())
            } else {
                SignInView(session: session)
            }
        }
        .tint(AppTheme.accent)
        .task { await session.restoreSession() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            session.refreshUsage(force: true)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
                guard !Task.isCancelled else { return }
                session.refreshUsage()
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await session.checkAppleCredential() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            session.signOut()
        }
    }
}

#Preview {
    ContentView()
}
