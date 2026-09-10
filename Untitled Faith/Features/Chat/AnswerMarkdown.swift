import MarkdownUI
import SwiftUI

struct AnswerMarkdown: View {
    private let content: MarkdownContent
    private let sources: Set<URL>

    init(_ text: String, sources: [AnswerSource]) {
        content = MarkdownContent(text.trimmingCharacters(in: .whitespacesAndNewlines))
        self.sources = Set(sources.map(\.url))
    }

    var body: some View {
        Markdown(content)
            .markdownTheme(.faithAnswer)
            .markdownImageProvider(NoAnswerImages())
            .markdownInlineImageProvider(NoAnswerImages())
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard let canonical = AnswerSource.canonicalURL(url), sources.contains(canonical) else { return .discarded }
                return .systemAction(canonical)
            })
    }
}

private extension Theme {
    static let faithAnswer = Theme.gitHub
        .text {
            ForegroundColor(.primary)
            FontSize(17)
        }
        .link { ForegroundColor(AppTheme.accent); UnderlineStyle(.single) }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.45)) }
                .markdownMargin(top: 20, bottom: 12)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.25)) }
                .markdownMargin(top: 18, bottom: 10)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.1)) }
                .markdownMargin(top: 16, bottom: 8)
        }
        .paragraph { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 0, bottom: 12)
        }
        .listItem { configuration in
            configuration.label.markdownMargin(top: 4)
        }
        .codeBlock { configuration in
            ViewThatFits(in: .horizontal) {
                Text(configuration.content)
                    .font(.system(.subheadline, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(14)
                ScrollView(.horizontal) {
                    Text(configuration.content)
                        .font(.system(.subheadline, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(14)
                }
            }
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .markdownMargin(top: 4, bottom: 12)
        }
}

// Generated Markdown must not silently fetch third-party images or tracking pixels.
private struct NoAnswerImages: ImageProvider, InlineImageProvider {
    func makeImage(url: URL?) -> some View { EmptyView() }
    func image(with url: URL, label: String) async throws -> Image { Image(systemName: "photo") }
}
