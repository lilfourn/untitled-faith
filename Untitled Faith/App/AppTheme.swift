import SwiftUI

enum AppTheme {
    static let appearanceStorageKey = "appearance"

    enum Appearance: String {
        case system, light, dark

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    static let background = Color("AppBackground")
    static let surface = Color(uiColor: UIColor { traits in
        UIColor(white: traits.userInterfaceStyle == .dark ? 0.12 : 1, alpha: 1)
    })
    static let accent = Color("AccentColor")
}
