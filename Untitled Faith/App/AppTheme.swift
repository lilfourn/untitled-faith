import SwiftUI

enum AppTheme {
    static let background = Color(uiColor: UIColor { traits in
        UIColor(white: traits.userInterfaceStyle == .dark ? 0.06 : 0.97, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        UIColor(white: traits.userInterfaceStyle == .dark ? 0.12 : 1, alpha: 1)
    })
    static let accent = Color("AccentColor")
}
