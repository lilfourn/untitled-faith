import SwiftUI

struct ContributionNumberPad: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    @ScaledMetric(relativeTo: .title2) private var keyHeight = 52
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "delete"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 6) {
            ForEach(keys, id: \.self) { key in
                Button {
                    if key == "delete" { onDelete() }
                    else { onDigit(key) }
                } label: {
                    Group {
                        if key == "delete" { Image(systemName: "delete.left").font(.title3) }
                        else { Text(key).font(.system(.title2, design: .rounded).weight(.medium)) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: keyHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ContributionKeyStyle())
                .accessibilityLabel(key == "delete" ? "Delete last digit" : key == "." ? "Decimal point" : key)
                .accessibilityIdentifier("contribution-key-\(key)")
            }
        }
    }
}

private struct ContributionKeyStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppTheme.accent)
            .background(configuration.isPressed ? AppTheme.accent.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 20))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.22), value: configuration.isPressed)
    }
}
