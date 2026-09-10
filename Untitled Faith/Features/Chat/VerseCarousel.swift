import SwiftUI

/// Draws a fresh verse on each open and crossfades between random verses without
/// repeating the last one shown, including across launches.
struct VerseCarousel: View {
    let draw: (String) async -> ScriptureCitation?
    var interval: Duration = .seconds(10)
    @State private var verse: ScriptureCitation?
    @State private var isLoading = true
    @AppStorage("homeVerse.lastReference") private var lastReference = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(draw: @escaping (String) async -> ScriptureCitation?, interval: Duration = .seconds(10)) {
        self.draw = draw
        self.interval = interval
    }

    var body: some View {
        ZStack {
            if let verse {
                VerseText(verse: verse)
                    .id(verse.id)
                    .transition(.opacity)
            } else if isLoading {
                VerseSkeleton()
            } else {
                Text("ESV verses are temporarily unavailable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await drawVerse(animated: false)
            await cycle()
        }
    }

    private func drawVerse(animated: Bool) async {
        let next = await draw(lastReference)
        guard !Task.isCancelled else { return }
        isLoading = false
        guard let next else { return }
        withAnimation(animated && !reduceMotion ? .easeInOut(duration: 0.8) : nil) {
            verse = next
            lastReference = next.reference
        }
    }

    private func cycle() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await drawVerse(animated: true)
        }
    }
}

private struct VerseSkeleton: View {
    @ScaledMetric(relativeTo: .title3) private var lineHeight = 18
    @ScaledMetric(relativeTo: .subheadline) private var referenceHeight = 14

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .frame(height: lineHeight)
                RoundedRectangle(cornerRadius: 4)
                    .frame(height: lineHeight)
                RoundedRectangle(cornerRadius: 4)
                    .frame(height: lineHeight)
                    .padding(.horizontal, 36)
            }
            RoundedRectangle(cornerRadius: 4)
                .frame(maxWidth: 140)
                .frame(height: referenceHeight)
        }
        .foregroundStyle(.quaternary)
        .frame(maxWidth: 480)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading ESV verse")
    }
}

private struct VerseText: View {
    let verse: ScriptureCitation
    private static let passageFont = Font.title3

    var body: some View {
        VStack(spacing: 14) {
            Text(passage)
                .font(Self.passageFont)
                .lineSpacing(4)
                .foregroundStyle(.secondary)
            Text("\(verse.reference) (\(verse.translation))")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 480)
        .accessibilityElement(children: .combine)
    }

    /// Render the divine name in small capitals.
    private var passage: AttributedString {
        var name = AttributedString("Lord")
        name.font = Self.passageFont.lowercaseSmallCaps()
        return verse.passage.components(separatedBy: "LORD").enumerated().reduce(into: AttributedString()) { result, part in
            if part.offset > 0 { result.append(name) }
            result.append(AttributedString(part.element))
        }
    }
}
