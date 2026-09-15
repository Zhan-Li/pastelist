import AppKit
import SwiftUI

/// A plain text view that behaves like a checklist document:
/// - ⌘V pastes plain text; Tab turns the current or selected lines into `☐ item`
///   lines (Shift-Tab takes the boxes off again)
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

extension NSAttributedString.Key {
    /// Bool: marks a checkbox character. Its glyph is drawn transparent and a
    /// real box is painted over it by `ChecklistLayoutManager`.
    static let checklistMarker = NSAttributedString.Key("pastelist.marker")
}

/// Paints SF Symbol checkboxes where the document has ☐ / ☑ characters. The
/// characters stay in the text (so copy, undo and persistence are plain
/// strings); only their pixels are replaced.
final class ChecklistLayoutManager: NSLayoutManager {
    static let boxSize: CGFloat = 15
    static let baseFont = NSFont.systemFont(ofSize: 14)

    /// Where the box for the marker at character `charIndex` is drawn, in text view coordinates
    /// (before the text container origin is applied).
    func boxRect(forMarkerAt charIndex: Int) -> NSRect? {
        let g = glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
        guard g.length > 0, let container = textContainer(forGlyphAt: g.location, effectiveRange: nil) else { return nil }
        let lineRect = lineFragmentRect(forGlyphAt: g.location, effectiveRange: nil)
        let baseline = lineRect.minY + location(forGlyphAt: g.location).y
        let glyphRect = boundingRect(forGlyphRange: g, in: container)
        let size = Self.boxSize
        let capMid = baseline - Self.baseFont.capHeight / 2
        return NSRect(x: glyphRect.minX + 1, y: (capMid - size / 2).rounded(), width: size, height: size)
    }

    /// An open item is a quiet rounded outline. A done one is the same shape
    /// with a soft accent tint and a checkmark — finished, not shouting.
    static func drawBox(in rect: NSRect, done: Bool) {
        let box = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 4.5, yRadius: 4.5)
        box.lineWidth = 1.5
        let accent = NSColor.controlAccentColor

        if done {
            accent.withAlphaComponent(0.14).setFill()
            box.fill()
            accent.withAlphaComponent(0.55).setStroke()
            box.stroke()

            // Checkmark. The view is flipped, so y grows downward.
            let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
            let check = NSBezierPath()
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: NSPoint(x: x + w * 0.28, y: y + h * 0.53))
            check.line(to: NSPoint(x: x + w * 0.44, y: y + h * 0.70))
            check.line(to: NSPoint(x: x + w * 0.74, y: y + h * 0.33))
            accent.setStroke()
            check.stroke()
        } else {
            NSColor.labelColor.withAlphaComponent(0.03).setFill()
            box.fill()
            NSColor.secondaryLabelColor.withAlphaComponent(0.7).setStroke()
            box.stroke()
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.checklistMarker, in: chars, options: []) { value, range, _ in
            guard let done = value as? Bool, var rect = boxRect(forMarkerAt: range.location) else { return }
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            Self.drawBox(in: rect, done: done)
        }
    }
}

final class ChecklistNSTextView: NSTextView {
    private let baseFont = ChecklistLayoutManager.baseFont
    /// The marker character reserves the box's horizontal space; its own glyph is invisible.
    private let markerFont = NSFont(name: "Apple Symbols", size: 16) ?? NSFont.systemFont(ofSize: 16)
    private lazy var markerAdvance: CGFloat =
        NSAttributedString(string: String(Marker.todo), attributes: [.font: markerFont]).size().width
    private lazy var markerKern: CGFloat =
        max(0, ChecklistLayoutManager.boxSize + 5 - markerAdvance)
    private lazy var spaceAdvance: CGFloat =
        NSAttributedString(string: " ", attributes: [.font: baseFont]).size().width

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    convenience init() {
        // Build our own container so the view tracks the scroll view's width.
        let storage = NSTextStorage()
        let layout = ChecklistLayoutManager()
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

    /// Paste is just paste. Text lands exactly as copied; Tab makes it a list.
    override func paste(_ sender: Any?) {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return }
        let s = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        insertText(s, replacementRange: selectedRange())
    }

    // MARK: - Tab: make lines into items

    override func insertTab(_ sender: Any?) { convertLines(toList: true) }
    override func insertBacktab(_ sender: Any?) { convertLines(toList: false) }

    /// Every line touched by the selection (or the cursor's line) gets a box,
    /// with bullets, numbering and existing checkbox syntax cleaned off — or
    /// loses its box on Shift-Tab.
    private func convertLines(toList: Bool) {
        let sel = selectedRange()
        // A selection ending right after a newline should not drag in the next line.
        var probe = sel
        if probe.length > 0, ns.character(at: probe.location + probe.length - 1) == 0x0A { probe.length -= 1 }
        let (body, text) = lineBody(ns.lineRange(for: probe))

        let converted = text.components(separatedBy: "\n").map { line -> String in
            if toList {
                if hasMarker(line) { return line }
                if let item = ChecklistParser.parse(line).first { return Marker.line(item.text, done: item.done) }
                return "\(Marker.todo) "
            } else {
                guard hasMarker(line) else { return line }
                return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }.joined(separator: "\n")

        guard converted != text else { return }
        replace(body, with: converted)
        let newLen = (converted as NSString).length
        if sel.length == 0 {
            setSelectedRange(NSRange(location: body.location + newLen, length: 0))
        } else {
            setSelectedRange(NSRange(location: body.location, length: newLen))
        }
    }

    // MARK: - Typing

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
        p.headIndent = markerAdvance + markerKern + spaceAdvance
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
                    .strikethroughColor: NSColor.labelColor.withAlphaComponent(0.45),
                    .foregroundColor: NSColor.labelColor.withAlphaComponent(0.72),
                ], range: r)
                storage.addAttributes(self.markerAttributes(done: true), range: markerR)
            } else if first == Marker.todo.utf16.first! {
                storage.addAttributes(self.markerAttributes(done: false), range: markerR)
            }
        }
        storage.endEditing()
        typingAttributes = baseAttributes
        window?.invalidateCursorRects(for: self)
    }

    private func markerAttributes(done: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: markerFont,
            .foregroundColor: NSColor.clear,
            .strikethroughStyle: 0,
            .kern: markerKern,
            .checklistMarker: done,
        ]
    }

    /// A pointing hand over every box, so it reads as clickable.
    override func resetCursorRects() {
        super.resetCursorRects()
        guard let lm = layoutManager as? ChecklistLayoutManager, let storage = textStorage else { return }
        let full = NSRange(location: 0, length: ns.length)
        storage.enumerateAttribute(.checklistMarker, in: full, options: []) { value, range, _ in
            guard value != nil, var r = lm.boxRect(forMarkerAt: range.location) else { return }
            r.origin.x += textContainerOrigin.x
            r.origin.y += textContainerOrigin.y
            addCursorRect(r.insetBy(dx: -2, dy: -2), cursor: .pointingHand)
        }
    }
}
