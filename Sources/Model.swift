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

/// One tab: a named checklist document with its own colour. Tabs are the
/// unit of persistence; the app holds a few of them and shows one at a time.
struct ListTab: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var text: String
    /// Index into `LabelColors.palette`. Picked least-used-first when the tab
    /// is made, so neighbouring tabs never share a colour by accident.
    var color: Int

    init(name: String, text: String = "", color: Int) {
        id = UUID()
        self.name = name
        self.text = text
        self.color = color
    }

    @MainActor var nsColor: NSColor { LabelColors.palette[color % LabelColors.palette.count] }
}

/// The tabs, which one is showing, and the cursor. Each tab's document is one
/// string, persisted as-is; the whole set is saved as JSON on every change.
@MainActor
final class DocStore: ObservableObject {
    @Published private(set) var tabs: [ListTab] {
        didSet {
            guard tabs != oldValue else { return }
            save()
            LabelColors.shared.prune(keeping: labels)
        }
    }
    @Published private(set) var currentID: UUID {
        didSet { UserDefaults.standard.set(currentID.uuidString, forKey: currentKey) }
    }
    /// Where the cursor is, so the Labels panel knows which line "this line" is.
    @Published var selection = NSRange(location: 0, length: 0)
    /// The live text view, for edits that must go through it (undo, selection).
    let textView = TextViewProxy()

    /// Each tab keeps its cursor while another tab is showing.
    private var savedSelections: [UUID: NSRange] = [:]

    private let tabsKey = "pastelist.tabs"
    private let currentKey = "pastelist.currentTab"
    /// 1.2 and earlier: one document, one string.
    private let legacyKey = "pastelist.document"

    init() {
        let defaults = UserDefaults.standard
        let loaded: [ListTab]
        if let data = defaults.data(forKey: tabsKey),
           let saved = try? JSONDecoder().decode([ListTab].self, from: data), !saved.isEmpty {
            loaded = saved
        } else {
            loaded = [ListTab(name: "List", text: defaults.string(forKey: legacyKey) ?? "", color: 0)]
        }
        let savedID = defaults.string(forKey: currentKey).flatMap(UUID.init)
        tabs = loaded
        currentID = loaded.first { $0.id == savedID }?.id ?? loaded[0].id
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tabs) {
            UserDefaults.standard.set(data, forKey: tabsKey)
        }
    }

    // MARK: - The current tab

    var currentIndex: Int { tabs.firstIndex { $0.id == currentID } ?? 0 }
    var current: ListTab { tabs[currentIndex] }

    /// The document that is showing. Edits land in the current tab.
    var text: String {
        get { current.text }
        set { tabs[currentIndex].text = newValue }
    }

    /// Done / total for the tab that is showing.
    var counts: (done: Int, total: Int) { ChecklistParser.counts(inDocument: text) }

    /// Done / total across every tab, for the menu bar icon.
    var totals: (done: Int, total: Int) {
        tabs.reduce((0, 0)) { acc, tab in
            let c = ChecklistParser.counts(inDocument: tab.text)
            return (acc.0 + c.done, acc.1 + c.total)
        }
    }

    /// Labels from every tab, so `#p1` on one list is one click away on another.
    var labels: [String] {
        Labels.all(inDocument: tabs.map(\.text).joined(separator: "\n"))
    }

    /// Lowercased names of the labels on the cursor's line.
    var labelsOnCurrentLine: Set<String> {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }
        let line = ns.lineRange(for: NSRange(location: min(selection.location, ns.length), length: 0))
        return Set(Labels.tokens(in: ns, range: line).map { $0.name.lowercased() })
    }

    // MARK: - Tabs

    func select(_ id: UUID) {
        guard id != currentID, tabs.contains(where: { $0.id == id }) else { return }
        savedSelections[currentID] = selection
        currentID = id
        selection = savedSelections[id] ?? NSRange(location: 0, length: 0)
    }

    func select(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        select(tabs[index].id)
    }

    /// Next (+1) or previous (-1) tab, wrapping around.
    func selectNeighbour(_ step: Int) {
        let n = tabs.count
        select(at: ((currentIndex + step) % n + n) % n)
    }

    /// A fresh tab after the current one, named "List N", in the least-used colour.
    func addTab() {
        tabs.insert(ListTab(name: freshName(), color: freshColor()), at: currentIndex + 1)
        select(tabs[currentIndex + 1].id)
    }

    func rename(_ id: UUID, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[i].name = name
    }

    /// Removes the tab. The last tab is not removed but emptied, so there is
    /// always something to type into.
    func close(_ id: UUID) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        savedSelections[id] = nil
        if tabs.count == 1 {
            tabs[0] = ListTab(name: "List", color: tabs[0].color)
            selection = NSRange(location: 0, length: 0)
            return
        }
        tabs.remove(at: i)
        if id == currentID {
            currentID = tabs[min(i, tabs.count - 1)].id
            selection = savedSelections[currentID] ?? NSRange(location: 0, length: 0)
        }
    }

    private func freshName() -> String {
        let taken = Set(tabs.map { $0.name.lowercased() })
        var n = tabs.count + 1
        while taken.contains("list \(n)") { n += 1 }
        return "List \(n)"
    }

    private func freshColor() -> Int {
        var counts = Array(repeating: 0, count: LabelColors.palette.count)
        for t in tabs { counts[t.color % counts.count] += 1 }
        // Least used; among those, the one furthest along from the current tab's colour
        // reads as most different next to it.
        let least = counts.min()!
        let from = current.color
        return counts.indices.filter { counts[$0] == least }
            .max { distance(from, $0) < distance(from, $1) }!
    }

    private func distance(_ a: Int, _ b: Int) -> Int {
        let n = LabelColors.palette.count, d = abs(a - b) % n
        return min(d, n - d)
    }

    // MARK: - Editing helpers

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
