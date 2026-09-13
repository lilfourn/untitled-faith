import SwiftUI

@main
struct UntitledFaithApp: App {
    @AppStorage(AppTheme.appearanceStorageKey) private var appearance: AppTheme.Appearance = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
