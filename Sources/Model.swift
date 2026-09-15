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

/// The document is one string, persisted as-is.
@MainActor
final class DocStore: ObservableObject {
    @Published var text: String {
        didSet { if text != oldValue { UserDefaults.standard.set(text, forKey: key) } }
    }

    private let key = "pastelist.document"

    init() {
        text = UserDefaults.standard.string(forKey: key) ?? ""
    }

    var counts: (done: Int, total: Int) { ChecklistParser.counts(inDocument: text) }

    func copyAsMarkdown() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(ChecklistParser.markdown(fromDocument: text), forType: .string)
    }

    func clear() { text = "" }
}
