import SwiftUI

// Reveal the already-formatted answer. Markdown syntax, citation blocks, and line wrapping stay stable.
struct AnswerReveal: ViewModifier {
    let progress: Double?
    @State private var height: CGFloat = 0

    private var visibleHeight: CGFloat { height * CGFloat(progress ?? 1) }

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: AnswerHeightKey.self, value: geometry.size.height)
                }
            }
            .onPreferenceChange(AnswerHeightKey.self) { height = $0 }
            .mask(alignment: .top) {
                if progress == nil || progress == 1 {
                    Rectangle()
                } else {
                    VStack(spacing: 0) {
                        Rectangle().frame(height: max(0, visibleHeight - 24))
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: min(24, visibleHeight))
                    }
                }
            }
            .frame(height: progress == nil ? nil : visibleHeight, alignment: .top)
            .clipped()
            .allowsHitTesting(progress == nil)
    }
}

private struct AnswerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
