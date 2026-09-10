import SwiftUI

struct DeveloperNoteDisclosure: View {
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(isExpanded ? "Hide developer’s note" : "Read developer’s note")
                        .font(.footnote)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.medium))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("developer-note-toggle")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                Text(Self.note)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(AppTheme.accent.opacity(0.78))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("developer-note-body")
                    .transition(.opacity)
                    .padding(.bottom, 12)
            }
        }
    }

    // Luke's note, with grammar, spelling, and punctuation corrections only.
    private static let note = """
    When making this app, I wanted it to be apparent to you and to myself that I am not here for the money. I truly believe that what I am building is for building God’s kingdom, not mine.

    That being said, I spend a lot of time working on this app, and I am currently a college student who wants to make this my full-time job. Please do not feel like you need to select any percentage to give to me, and I don’t expect you to.

    I am grateful for whatever you choose because I am doing this for God, not for you, me, or anyone else. This is all for the glory of God.

    - Luke Fournier (developer)
    """
}
