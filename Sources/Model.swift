import AppKit
import Foundation

/// The two glyphs that start a checklist line. They are real characters in the
/// document, so the text stays readable if it is copied anywhere else.
enum Marker {
    static let todo: Character = "☐"
    static let done: Character = "☑"

    static func isMarker(_ c: Character?) -> Bool { c == todo || c == done }

    static func line(_ text: String, done: Bool) -> String {
        "\(done ? Marker.done : Marker.todo) \(text)"
    }
}

struct ChecklistItem: Equatable {
    var text: String
    var done: Bool = false
}

/// Turns arbitrary pasted text into checklist items.
/// - one item per non-empty line
/// - strips leading bullets, numbers, and existing checkbox markers
/// - "- [x]", "☑", "✓", "✔" prefixes come in as already-done
enum ChecklistParser {
    private static let checkedPrefixes = ["[x]", "[X]", "☑", "☒", "✓", "✔", "🗹"]
    private static let uncheckedPrefixes = ["[ ]", "[]", "☐", "◻", "▢"]
    private static let bulletPrefixes = ["•", "◦", "▪", "▫", "‣", "-", "–", "—", "*", "+", ">"]

    static func parse(_ raw: String) -> [ChecklistItem] {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> ChecklistItem? in
                var s = line.trimmingCharacters(in: .whitespaces)
                if s.isEmpty { return nil }
                var done = false

                // Markers can stack ("- 1. [ ] foo"); a few passes covers real input.
                for _ in 0..<3 {
                    let before = s
                    s = stripBullet(s)
                    s = stripNumber(s)
                    if let (rest, isDone) = stripCheckbox(s) {
                        s = rest
                        done = done || isDone
                    }
                    s = s.trimmingCharacters(in: .whitespaces)
                    if s == before { break }
                }
                return s.isEmpty ? nil : ChecklistItem(text: s, done: done)
            }
    }

    /// The pasted block as it should appear in the document.
    static func document(_ items: [ChecklistItem]) -> String {
        items.map { Marker.line($0.text, done: $0.done) }.joined(separator: "\n")
    }

    /// The document as Markdown task-list syntax. Plain lines pass through.
    static func markdown(fromDocument doc: String) -> String {
        doc.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            guard let first = line.first, Marker.isMarker(first) else { return String(line) }
            let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
            return "- [\(first == Marker.done ? "x" : " ")] \(body)"
        }.joined(separator: "\n")
    }

    static func counts(inDocument doc: String) -> (done: Int, total: Int) {
        var done = 0, total = 0
        for line in doc.split(separator: "\n") {
            switch line.first {
            case Marker.done: done += 1; total += 1
            case Marker.todo: total += 1
            default: break
            }
        }
        return (done, total)
    }

    private static func stripBullet(_ s: String) -> String {
        for b in bulletPrefixes where s.hasPrefix(b) {
            let rest = s.dropFirst(b.count)
            // Require whitespace after the bullet so "-5 degrees" or "*bold*" survive.
            if rest.first?.isWhitespace == true { return String(rest).trimmingCharacters(in: .whitespaces) }
        }
        return s
    }

    /// "1. foo", "1) foo", "(1) foo", "a. foo", "iv. foo"
    private static func stripNumber(_ s: String) -> String {
        let pattern = #"^\(?(?:\d{1,3}|[a-zA-Z]|[ivxIVX]{1,5})[.)]\s+"#
        if let r = s.range(of: pattern, options: .regularExpression) {
            return String(s[r.upperBound...])
        }
        return s
    }

    private static func stripCheckbox(_ s: String) -> (String, Bool)? {
        for p in checkedPrefixes where s.hasPrefix(p) {
            return (String(s.dropFirst(p.count)), true)
        }
        for p in uncheckedPrefixes where s.hasPrefix(p) {
            return (String(s.dropFirst(p.count)), false)
        }
        return nil
    }
}

/// Labels are `#word` tokens typed on a line — `☐ fix login #p1 #blocked`.
/// The user invents them; nothing is predefined. A label is ordinary text in
/// the document, so it survives copy, undo, Markdown export and persistence.
enum Labels {
    /// `#` at the start of a line or after whitespace, then letters, digits, `_` or `-`.
    static let regex = try! NSRegularExpression(pattern: #"(?<![^\s])#([\p{L}\p{N}_\-]+)"#)

    /// Every label token in `s` (UTF-16 ranges that include the `#`) with its name.
    static func tokens(in s: NSString, range: NSRange? = nil) -> [(range: NSRange, name: String)] {
        let r = range ?? NSRange(location: 0, length: s.length)
        return regex.matches(in: s as String, range: r).map { ($0.range, s.substring(with: $0.range(at: 1))) }
    }

    /// Distinct labels in the document, in order of first appearance, spelled
    /// the way they were first typed. Matching is case-insensitive.
    static func all(inDocument doc: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for t in tokens(in: doc as NSString) where seen.insert(t.name.lowercased()).inserted {
            out.append(t.name)
        }
        return out
    }

    /// What a name typed into the Labels panel becomes: no leading `#`, spaces
    /// turn into dashes, anything else unusable is dropped. Nil if nothing is left.
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("#") { s.removeFirst() }
        s = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: "-")
        s = String(s.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        return s.isEmpty ? nil : s
    }
}

/// Gives each label a colour the first time it is seen and remembers it, so
/// `#p1` stays the same colour for as long as it is in the document. A new
/// label takes the least-used colour, so a handful of labels always look
/// different from each other.
@MainActor
final class LabelColors {
    static let shared = LabelColors()
    static let palette: [NSColor] = [
        .systemBlue, .systemOrange, .systemGreen, .systemPurple, .systemPink, .systemTeal,
        .systemYellow, .systemIndigo, .systemRed, .systemBrown, .systemMint, .systemCyan,
    ]

    private let key = "pastelist.labelColors"
    private var assigned: [String: Int]   // lowercased name → palette index

    private init() {
        assigned = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    func color(for name: String) -> NSColor {
        let k = name.lowercased()
        if let i = assigned[k], i < Self.palette.count { return Self.palette[i] }
        var counts = Array(repeating: 0, count: Self.palette.count)
        for i in assigned.values where i < counts.count { counts[i] += 1 }
        let i = counts.indices.min { (counts[$0], $0) < (counts[$1], $1) }!
        assigned[k] = i
        save()
        return Self.palette[i]
    }

    /// The label's text colour: its hue pulled towards the label colour of the
    /// current appearance, so yellow is readable on white and blue on black.
    static func textColor(for color: NSColor) -> NSColor {
        color.blended(withFraction: 0.35, of: .labelColor) ?? color
    }

    /// Forget labels that have left the document, so their colours free up.
    func prune(keeping names: [String]) {
        let live = Set(names.map { $0.lowercased() })
        let before = assigned.count
        assigned = assigned.filter { live.contains($0.key) }
        if assigned.count != before { save() }
    }

    private func save() { UserDefaults.standard.set(assigned, forKey: key) }
}

/// The document is one string, persisted as-is.
@MainActor
final class DocStore: ObservableObject {
    @Published var text: String {
        didSet {
            guard text != oldValue else { return }
            UserDefaults.standard.set(text, forKey: key)
            LabelColors.shared.prune(keeping: labels)
        }
    }
    /// Where the cursor is, so the Labels panel knows which line "this line" is.
    @Published var selection = NSRange(location: 0, length: 0)
    /// The live text view, for edits that must go through it (undo, selection).
    let textView = TextViewProxy()

    private let key = "pastelist.document"

    init() {
        text = UserDefaults.standard.string(forKey: key) ?? ""
    }

    var counts: (done: Int, total: Int) { ChecklistParser.counts(inDocument: text) }

    var labels: [String] { Labels.all(inDocument: text) }

    /// Lowercased names of the labels on the cursor's line.
    var labelsOnCurrentLine: Set<String> {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }
        let line = ns.lineRange(for: NSRange(location: min(selection.location, ns.length), length: 0))
        return Set(Labels.tokens(in: ns, range: line).map { $0.name.lowercased() })
    }

    /// Puts `#name` on the current line, or takes it off if it is already there.
    func toggleLabel(_ name: String) { textView.view?.setLabel(name, on: nil) }

    /// Puts `#name` on the current line (a no-op if it is already there).
    func addLabel(_ name: String) { textView.view?.setLabel(name, on: true) }

    func focusDocument() {
        if let tv = textView.view { tv.window?.makeFirstResponder(tv) }
    }

    func copyAsMarkdown() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(ChecklistParser.markdown(fromDocument: text), forType: .string)
    }

    func clear() { text = "" }
}
