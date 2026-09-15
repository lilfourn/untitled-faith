import SwiftUI

/// Native multiline input exposes the caret so @ search also works while editing earlier text.
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var focused: Bool

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = UIEdgeInsets(top: 15, left: 20, bottom: 15, right: 0)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityIdentifier = "question-input"
        view.accessibilityLabel = "Question"
        view.accessibilityHint = "Type @ to find and attach Bible verses."
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        guard view.markedTextRange == nil else { return }
        if view.text != text { view.text = text }
        let bounded = NSRange(location: min(selection.location, text.utf16.count),
                              length: min(selection.length, max(0, text.utf16.count - selection.location)))
        if view.selectedRange != bounded { view.selectedRange = bounded }
        if focused && !view.isFirstResponder { view.becomeFirstResponder() }
        else if !focused && view.isFirstResponder { view.resignFirstResponder() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let lineHeight = uiView.font?.lineHeight ?? 22
        let maximum = lineHeight * 6 + 30
        uiView.isScrollEnabled = height > maximum
        return CGSize(width: width, height: min(max(height, lineHeight + 30), maximum))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView
        var updating = false
        init(parent: ComposerTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            guard !updating else { return }
            parent.text = textView.text
            parent.selection = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !updating else { return }
            parent.selection = textView.selectedRange
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !updating { parent.focused = true }
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            if !updating { parent.focused = false }
        }
    }
}
