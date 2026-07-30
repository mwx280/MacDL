import SwiftUI
import AppKit

private final class PlaceholderTextView: NSTextView {
    var placeholder: String = ""
    private var drawingRect: NSRect { bounds.insetBy(dx: textContainerInset.width + 2, dy: textContainerInset.height) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        placeholder.draw(in: drawingRect, withAttributes: attrs)
    }
}

struct PlaceholderTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder

        let tv = PlaceholderTextView()
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.font = font
        tv.string = text
        tv.placeholder = placeholder
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = NSSize(width: 4, height: 3)
        tv.delegate = context.coordinator
        tv.allowsUndo = true

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? PlaceholderTextView else { return }
        if tv.string != text {
            tv.string = text
        }
        tv.font = font
        tv.placeholder = placeholder
        tv.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
        }
    }
}
