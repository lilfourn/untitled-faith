import SwiftUI

/// Cycles through verses with a crossfade, starting from a day-of-year offset so the
/// first verse changes daily.
struct VerseCarousel: View {
    let verses: [ScriptureCitation]
    var interval: Duration = .seconds(10)
    @State private var index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(verses: [ScriptureCitation], interval: Duration = .seconds(10)) {
        self.verses = verses
        self.interval = interval
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        _index = State(initialValue: verses.isEmpty ? 0 : day % verses.count)
    }

    var body: some View {
        ZStack {
            if verses.indices.contains(index) {
                VerseText(verse: verses[index])
                    .id(verses[index].id)
                    .transition(.opacity)
            }
        }
        .task(id: verses.count) { await cycle() }
    }

    private func cycle() async {
        guard verses.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) {
                index = (index + 1) % verses.count
            }
        }
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

    /// ESV prints the divine name as "Lord" in small capitals.
    private var passage: AttributedString {
        var name = AttributedString("Lord")
        name.font = Self.passageFont.lowercaseSmallCaps()
        return verse.passage.components(separatedBy: "LORD").enumerated().reduce(into: AttributedString()) { result, part in
            if part.offset > 0 { result.append(name) }
            result.append(AttributedString(part.element))
        }
    }
}
