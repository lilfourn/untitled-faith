import SwiftUI

/// Matches the system launch screen while the saved session and first screen are prepared.
struct AppLoadingView: View {
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ProgressView()
                .tint(.secondary)
                .accessibilityLabel("Opening Untitled Faith")
        }
    }
}
