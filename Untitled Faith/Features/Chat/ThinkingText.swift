import SwiftUI

struct ThinkingText: View {
    let title: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(title)
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                            let width = geometry.size.width * 0.65
                            LinearGradient(colors: [.clear, .primary.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: width)
                                .offset(x: -width + (geometry.size.width + width) * phase)
                        }
                    }
                    .mask(Text(title).font(.body.weight(.medium)))
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .accessibilityIdentifier("answer-loading-status")
    }
}
