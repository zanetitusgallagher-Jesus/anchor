import AppKit
import SwiftUI

/// NSTextView-backed rich text editor (bold, italic, bullet lists) that
/// round-trips RTF. macOS 14's SwiftUI TextEditor is plain text only.
struct RichTextEditor: NSViewRepresentable {
    @Binding var rtf: Data
    @Binding var plainText: String
    var font: NSFont = .init(name: "New York", size: 16) ?? .systemFont(ofSize: 16)
    let controller: RichTextController

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = true
        tv.allowsUndo = true
        tv.importsGraphics = false
        tv.drawsBackground = false
        tv.font = font
        tv.textColor = .labelColor
        tv.textContainerInset = NSSize(width: 6, height: 10)
        tv.isAutomaticQuoteSubstitutionEnabled = true
        tv.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
        tv.delegate = context.coordinator
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        if !rtf.isEmpty, let attr = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            tv.textStorage?.setAttributedString(attr)
        }
        controller.textView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        init(_ parent: RichTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, let storage = tv.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            parent.rtf = storage.rtf(from: range, documentAttributes: [:]) ?? Data()
            parent.plainText = storage.string
        }
    }
}

/// Lets SwiftUI toolbar buttons act on the editor's selection.
final class RichTextController {
    weak var textView: NSTextView?

    enum Trait { case bold, italic }

    @MainActor
    func toggle(_ trait: Trait) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let mask: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask
        let fm = NSFontManager.shared
        let range = tv.selectedRange()
        if range.length == 0 {
            let current = (tv.typingAttributes[.font] as? NSFont) ?? tv.font ?? .systemFont(ofSize: 16)
            let has = fm.traits(of: current).contains(mask)
            tv.typingAttributes[.font] = has ? fm.convert(current, toNotHaveTrait: mask) : fm.convert(current, toHaveTrait: mask)
            return
        }
        // If every run already has the trait, remove it; otherwise add it.
        var allHave = true
        storage.enumerateAttribute(.font, in: range) { value, _, _ in
            if let f = value as? NSFont, !fm.traits(of: f).contains(mask) { allHave = false }
        }
        guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let f = (value as? NSFont) ?? tv.font ?? .systemFont(ofSize: 16)
            storage.addAttribute(.font, value: allHave ? fm.convert(f, toNotHaveTrait: mask) : fm.convert(f, toHaveTrait: mask), range: sub)
        }
        storage.endEditing()
        tv.didChangeText()
    }

    @MainActor
    func bullet() {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let line = ns.lineRange(for: NSRange(location: tv.selectedRange().location, length: 0))
        let insertAt = NSRange(location: line.location, length: 0)
        if tv.shouldChangeText(in: insertAt, replacementString: "• ") {
            tv.textStorage?.replaceCharacters(in: insertAt, with: NSAttributedString(string: "• ", attributes: tv.typingAttributes))
            tv.didChangeText()
        }
    }
}

struct RichTextToolbar: View {
    let controller: RichTextController
    var body: some View {
        HStack(spacing: 4) {
            Button { controller.toggle(.bold) } label: { Image(systemName: "bold") }.help("Bold")
            Button { controller.toggle(.italic) } label: { Image(systemName: "italic") }.help("Italic")
            Button { controller.bullet() } label: { Image(systemName: "list.bullet") }.help("Bullet")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.secondaryInk)
    }
}
