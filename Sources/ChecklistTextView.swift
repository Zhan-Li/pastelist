import AppKit
import SwiftUI

/// A plain text view that behaves like a checklist document:
/// - ⌘V reformats the clipboard into `☐ item` lines
/// - Enter starts a new item; Enter on an empty item removes its box
/// - Backspace right after a box removes the box
/// - clicking a box toggles it; ⌘↩ toggles the current line
/// - done lines are struck through
struct ChecklistTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let tv = ChecklistNSTextView()
        tv.delegate = context.coordinator
        tv.string = text
        tv.restyle()

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? ChecklistNSTextView, tv.string != text else { return }
        tv.string = text
        tv.restyle()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChecklistTextView
        init(_ parent: ChecklistTextView) { self.parent = parent }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? ChecklistNSTextView else { return }
            tv.restyle()
            parent.text = tv.string
        }
    }
}

final class ChecklistNSTextView: NSTextView {
    private let baseFont = NSFont.systemFont(ofSize: 14)
    /// Both box glyphs from one face so they match in weight and size.
    private let markerFont = NSFont(name: "Apple Symbols", size: 16) ?? NSFont.systemFont(ofSize: 16)

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    convenience init() {
        // Build our own container so the view tracks the scroll view's width.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configure() {
        isRichText = true            // we set attributes ourselves…
        importsGraphics = false      // …but never accept anyone else's
        usesFontPanel = false
        usesInspectorBar = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        drawsBackground = false
        font = baseFont
        textContainerInset = NSSize(width: 14, height: 14)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        typingAttributes = baseAttributes
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // Only ever read plain text off the pasteboard, including for drag-and-drop.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    // MARK: - Line helpers

    private var ns: NSString { string as NSString }

    private func lineRange(at location: Int) -> NSRange {
        ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
    }

    /// The line's contents without its trailing newline.
    private func lineBody(_ r: NSRange) -> (range: NSRange, text: String) {
        var body = r
        let s = ns.substring(with: r)
        if s.hasSuffix("\n") { body.length -= 1 }
        return (body, ns.substring(with: body))
    }

    private func hasMarker(_ line: String) -> Bool { Marker.isMarker(line.first) }

    /// "☐ " with nothing after it.
    private func isBareMarkerLine(_ line: String) -> Bool {
        hasMarker(line) && line.dropFirst().trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func replace(_ range: NSRange, with s: String, select: Int? = nil) {
        guard shouldChangeText(in: range, replacementString: s) else { return }
        textStorage?.replaceCharacters(in: range, with: s)
        didChangeText()
        if let select { setSelectedRange(NSRange(location: select, length: 0)) }
    }

    // MARK: - Paste

    override func paste(_ sender: Any?) {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return }
        let items = ChecklistParser.parse(raw)
        guard !items.isEmpty else { return }

        let sel = selectedRange()
        let line = lineRange(at: sel.location)
        let (body, bodyText) = lineBody(line)
        let block = ChecklistParser.document(items)

        // Single line pasted into the middle of an item: just text, no new box.
        if items.count == 1, sel.location > line.location, !isBareMarkerLine(bodyText) {
            insertText(items[0].text, replacementRange: sel)
            return
        }

        if bodyText.trimmingCharacters(in: .whitespaces).isEmpty || isBareMarkerLine(bodyText) {
            // Empty line: it becomes the pasted block.
            replace(body, with: block, select: body.location + (block as NSString).length)
        } else if sel.location >= body.location + body.length {
            // End of a line: the block goes underneath.
            let s = "\n" + block
            replace(sel, with: s, select: sel.location + (s as NSString).length)
        } else {
            // Mid-line: split the line around the block.
            let s = "\n" + block + "\n"
            replace(sel, with: s, select: sel.location + (s as NSString).length - 1)
        }
    }

    // MARK: - Typing

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // First keystroke in an empty document gets a box for free.
        if ns.length == 0, let s = string as? String, !s.isEmpty, !s.hasPrefix("\n") {
            super.insertText("\(Marker.todo) " + s, replacementRange: replacementRange)
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func insertNewline(_ sender: Any?) {
        let sel = selectedRange()
        let line = lineRange(at: sel.location)
        let (body, bodyText) = lineBody(line)

        if isBareMarkerLine(bodyText) {
            // Enter on an empty item: drop the box, leaving a plain blank line.
            replace(body, with: "", select: body.location)
            return
        }
        // Continue the list if we are on an item, otherwise a plain newline.
        let s = hasMarker(bodyText) ? "\n\(Marker.todo) " : "\n"
        replace(sel, with: s, select: sel.location + (s as NSString).length)
    }

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0 {
            let line = lineRange(at: sel.location)
            let (_, bodyText) = lineBody(line)
            // Cursor sits right after "☐ ": remove the box, keep the text.
            let markerLen = hasMarker(bodyText) ? (bodyText.dropFirst().first == " " ? 2 : 1) : 0
            if markerLen > 0, sel.location == line.location + markerLen {
                replace(NSRange(location: line.location, length: markerLen), with: "", select: line.location)
                return
            }
        }
        super.deleteBackward(sender)
    }

    // MARK: - Toggling

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let idx = characterIndexForInsertion(at: p)
        if let r = markerRange(near: idx) {
            toggle(r)
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.keyCode == 36 /* return */ {
            let line = lineRange(at: selectedRange().location)
            if hasMarker(lineBody(line).text) { toggle(NSRange(location: line.location, length: 1)) }
            return
        }
        super.keyDown(with: event)
    }

    /// The box on the line containing `idx`, if `idx` is on or just after it.
    private func markerRange(near idx: Int) -> NSRange? {
        guard ns.length > 0 else { return nil }
        let line = lineRange(at: idx)
        guard hasMarker(lineBody(line).text), idx <= line.location + 1 else { return nil }
        return NSRange(location: line.location, length: 1)
    }

    private func toggle(_ r: NSRange) {
        let sel = selectedRange()
        let cur = ns.substring(with: r)
        let new = cur == String(Marker.todo) ? String(Marker.done) : String(Marker.todo)
        replace(r, with: new)
        setSelectedRange(sel)
    }

    // MARK: - Styling

    private var paragraphStyle: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        p.paragraphSpacing = 2
        // Wrapped lines indent under the text, not under the box.
        p.headIndent = 22
        return p
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraphStyle]
    }

    /// Re-derive all attributes from the text. Cheap for a checklist-sized document.
    func restyle() {
        guard let storage = textStorage else { return }
        let full = NSRange(location: 0, length: ns.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)
        ns.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, r, _, _ in
            guard r.length > 0 else { return }
            let first = self.ns.character(at: r.location)
            let markerR = NSRange(location: r.location, length: 1)
            if first == Marker.done.utf16.first! {
                storage.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: NSColor.tertiaryLabelColor,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ], range: r)
                storage.addAttributes([
                    .font: self.markerFont,
                    .foregroundColor: NSColor.controlAccentColor,
                    .strikethroughStyle: 0,
                ], range: markerR)
            } else if first == Marker.todo.utf16.first! {
                storage.addAttributes([
                    .font: self.markerFont,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ], range: markerR)
            }
        }
        storage.endEditing()
        typingAttributes = baseAttributes
    }
}
