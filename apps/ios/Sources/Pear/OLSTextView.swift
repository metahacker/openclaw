import SwiftUI
import UIKit

/// UIKit-backed multiline editor for the OLS composer and voice draft.
///
/// SwiftUI's vertical-axis `TextField` is backed by a UITextView that re-measures against
/// the SwiftUI frame on every UIKit layout pass; with a custom font on iOS 26 the two never
/// agree once the field has content, and the CI sample showed the main thread spinning in
/// `_UIHostingView.beginTransaction` for minutes. Upstream's iOS chat composer avoids the
/// same thing by owning the UITextView; this mirrors that shape with OLS typography.
@MainActor
struct OLSTextView: UIViewRepresentable {
    @Binding var text: String
    var minLines: Int
    var maxLines: Int
    var isEnabled = true
    var accessibilityLabel: String
    var accessibilityIdentifier: String
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.font = OLSTheme.bodyUIFont
        view.adjustsFontForContentSizeCategory = true
        view.textColor = UIColor(OLSTheme.ink)
        view.tintColor = UIColor(OLSTheme.accent)
        view.allowsEditingTextAttributes = false
        view.isScrollEnabled = true
        view.showsVerticalScrollIndicator = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.returnKeyType = .default
        view.accessibilityLabel = self.accessibilityLabel
        view.accessibilityIdentifier = self.accessibilityIdentifier
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        view.text = self.text
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = self.isEnabled
        if !self.isEnabled, view.isFirstResponder {
            view.resignFirstResponder()
        }
        // SwiftUI echoes the value the coordinator just reported; resetting the text
        // while typing would move the caret and fight autocorrection.
        if view.isFirstResponder, context.coordinator.lastReportedText == self.text {
            return
        }
        if view.text != self.text {
            context.coordinator.isProgrammaticUpdate = true
            defer { context.coordinator.isProgrammaticUpdate = false }
            view.text = self.text
            if view.isFirstResponder {
                view.selectedRange = NSRange(location: (self.text as NSString).length, length: 0)
            }
            view.invalidateIntrinsicContentSize()
        }
        context.coordinator.lastReportedText = self.text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context _: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let line = uiView.font?.lineHeight ?? 22
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        let minHeight = ceil(line * CGFloat(self.minLines))
        let maxHeight = ceil(line * CGFloat(self.maxLines))
        return CGSize(width: width, height: min(max(ceil(fitting.height), minHeight), maxHeight))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: OLSTextView
        var isProgrammaticUpdate = false
        var lastReportedText: String?

        init(_ parent: OLSTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_: UITextView) {
            self.parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_: UITextView) {
            self.parent.onFocusChange(false)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !self.isProgrammaticUpdate else { return }
            self.lastReportedText = textView.text
            self.parent.text = textView.text
            textView.invalidateIntrinsicContentSize()
        }
    }
}
