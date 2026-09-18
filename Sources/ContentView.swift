import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DocStore
    @State private var tip: String?
    @State private var showShortcuts = false
    @State private var showLabels = false

    var body: some View {
        let text = Binding(get: { store.text }, set: { store.text = $0 })
        VStack(spacing: 0) {
            TabBar()
            Divider()
            ZStack(alignment: .topLeading) {
                ChecklistTextView(text: text, selection: $store.selection, tabID: store.currentID, proxy: store.textView)
                if store.text.isEmpty { placeholder }
            }
            .overlay(alignment: .bottomTrailing) {
                if let tip {
                    Text(tip)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                        .padding(.trailing, 10)
                        .padding(.bottom, 6)
                        .transition(.opacity)
                }
            }
            if showLabels {
                Divider()
                LabelsPanel()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if showShortcuts {
                Divider()
                ShortcutsPanel()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            footer
        }
        .frame(width: 380, height: 480)
        .animation(.easeOut(duration: 0.12), value: tip)
        .animation(.easeOut(duration: 0.18), value: showShortcuts)
        .animation(.easeOut(duration: 0.18), value: showLabels)
    }

    private func toggleLabels() {
        showLabels.toggle()
        if showLabels { showShortcuts = false } else { store.focusDocument() }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Paste anything here.")
            Text("Press Tab on a line to give it a checkbox.")
        }
        .foregroundStyle(.tertiary)
        .font(.system(size: 14))
        .padding(.horizontal, 19)
        .padding(.vertical, 14)
        .allowsHitTesting(false)
    }

    private var footer: some View {
        let c = store.counts
        return HStack(spacing: 4) {
            Text(c.total == 0 ? "" : "\(c.done) of \(c.total) done")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            FooterButton("tag", "Labels  ⌘L", tip: $tip, active: showLabels) { toggleLabels() }
                .keyboardShortcut("l", modifiers: .command)
            FooterButton("keyboard", "Keyboard shortcuts", tip: $tip, active: showShortcuts) {
                showShortcuts.toggle()
                if showShortcuts { showLabels = false }
            }
            FooterButton("doc.on.doc", "Copy as Markdown  ⇧⌘C", tip: $tip) { store.copyAsMarkdown() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(store.text.isEmpty)
            FooterButton("trash", "Clear this list", tip: $tip) { store.clear() }
                .disabled(store.text.isEmpty)
            FooterButton("power", "Quit PasteList  ⌘Q", tip: $tip) { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

/// The tabs across the top: one chip per list, in its own colour. Click to
/// switch, double-click (or right-click ▸ Rename) to name it, + for a new one.
private struct TabBar: View {
    @EnvironmentObject var store: DocStore
    @State private var renaming: UUID?
    @State private var draft = ""
    @FocusState private var renameFocus: UUID?

    var body: some View {
        HStack(spacing: 4) {
            ScrollViewReader { scroller in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(store.tabs) { tab in
                            chip(tab).id(tab.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: store.currentID) { _, id in
                    withAnimation(.easeOut(duration: 0.15)) { scroller.scrollTo(id) }
                }
            }
            Button {
                commitRename()
                store.addTab()
                store.focusDocument()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New tab  ⌘T")
            .keyboardShortcut("t", modifiers: .command)
            .padding(.trailing, 8)
        }
        .frame(height: 34)
        .background(shortcuts)
        .onChange(of: renameFocus) { _, focus in
            // Clicking away from the name field keeps what was typed.
            if focus == nil, renaming != nil { commitRename() }
        }
    }

    /// Invisible buttons whose only job is to carry keyboard shortcuts.
    private var shortcuts: some View {
        Group {
            Button("") { store.selectNeighbour(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button("") { store.selectNeighbour(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
            ForEach(1..<10) { n in
                Button("") { store.select(at: n - 1) }
                    .keyboardShortcut(KeyEquivalent(Character(String(n))), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func chip(_ tab: ListTab) -> some View {
        let selected = tab.id == store.currentID
        let color = Color(nsColor: tab.nsColor)
        let ink = Color(nsColor: LabelColors.textColor(for: tab.nsColor))
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            if renaming == tab.id {
                TextField("Name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ink)
                    .focused($renameFocus, equals: tab.id)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                    .frame(width: 96)
            } else {
                Text(tab.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? ink : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 130)
            }
            if selected, renaming != tab.id {
                Button { store.close(tab.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ink.opacity(0.7))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(store.tabs.count == 1 ? "Empty this list" : "Close this tab")
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, selected && renaming != tab.id ? 5 : 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selected ? color.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(color.opacity(selected ? 0.45 : 0), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture { if renaming != tab.id { store.select(tab.id); store.focusDocument() } }
        .simultaneousGesture(TapGesture(count: 2).onEnded { if renaming != tab.id { beginRename(tab) } })
        .contextMenu {
            Button("Rename") { beginRename(tab) }
            Button("New Tab") { store.addTab() }
            Divider()
            Button(store.tabs.count == 1 ? "Empty This List" : "Close Tab") { store.close(tab.id) }
        }
        .help(renaming == tab.id ? "" : "Double-click to rename")
    }

    private func beginRename(_ tab: ListTab) {
        commitRename()
        store.select(tab.id)
        draft = tab.name
        renaming = tab.id
        // The field exists only after this update lands; focus it once it does.
        DispatchQueue.main.async { renameFocus = tab.id }
    }

    private func commitRename() {
        guard let id = renaming else { return }
        renaming = nil
        renameFocus = nil
        store.rename(id, to: draft)
        refocusDocument()
    }

    private func cancelRename() {
        renaming = nil
        renameFocus = nil
        refocusDocument()
    }

    /// SwiftUI settles its own focus after the field goes away; hand the
    /// keyboard back to the document once that has happened, not before.
    private func refocusDocument() {
        DispatchQueue.main.async { store.focusDocument() }
    }
}

private struct FooterButton: View {
    let symbol: String
    let help: String
    @Binding var tip: String?
    var active = false
    let action: () -> Void
    @State private var hovering = false

    init(_ symbol: String, _ help: String, tip: Binding<String?>, active: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self._tip = tip
        self.active = active
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : (hovering ? Color.primary : Color.secondary))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering || active ? Color.primary.opacity(0.07) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { over in
            hovering = over
            if over { tip = help } else if tip == help { tip = nil }
        }
    }
}

/// The labels in the document, as pills. Click one to put it on the current
/// line (or take it off); type a new one to invent it. Nothing is predefined —
/// a label exists because it is in the text.
private struct LabelsPanel: View {
    @EnvironmentObject var store: DocStore
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        let labels = store.labels
        let current = store.labelsOnCurrentLine
        VStack(alignment: .leading, spacing: 8) {
            if labels.isEmpty {
                Text("No labels yet. Type #p1, #blocked, any word, on a line — or add one here. Each gets its own colour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(labels, id: \.self) { name in
                        LabelPill(name: name, active: current.contains(name.lowercased())) {
                            store.toggleLabel(name)
                        }
                    }
                }
                Text("Click a label to put it on this line, or take it off.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                TextField("New label, e.g. p1 or blocked", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($editing)
                    .onSubmit(add)
                Button("Add", action: add)
                    .controlSize(.small)
                    .disabled(Labels.normalize(draft) == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
        .onAppear { editing = true }
    }

    private func add() {
        guard let name = Labels.normalize(draft) else { return }
        draft = ""
        store.addLabel(name)
        store.focusDocument()
    }
}

private struct LabelPill: View {
    let name: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        let color = LabelColors.shared.color(for: name)
        Button(action: action) {
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(nsColor: LabelColors.textColor(for: color)))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(nsColor: color).opacity(active ? 0.32 : 0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(Color(nsColor: color).opacity(active ? 0.7 : 0), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(active ? "Take #\(name) off this line" : "Put #\(name) on this line")
    }
}

/// Lays subviews out left to right, wrapping to a new row when they run out of room.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        place(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = place(in: bounds.width, subviews: subviews)
        for (i, p) in result.points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func place(in width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        var points: [CGPoint] = []
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), points)
    }
}

private struct ShortcutsPanel: View {
    private let rows: [(keys: [String], what: String)] = [
        (["⌘", "V"], "Paste text, exactly as copied"),
        (["⇥"], "Give this line (or every selected line) a checkbox"),
        (["⇧", "⇥"], "Take the checkbox off"),
        (["⌘", "↩"], "Tick or untick this line"),
        (["↩"], "Next item · on an empty item, drops its box"),
        (["⌫"], "Right after a box, removes the box"),
        (["#"], "Type #word on a line to label it · colours pick themselves"),
        (["⌘", "L"], "Labels: click one for this line, or add a new one"),
        (["⌘", "T"], "New tab · double-click a tab to rename it"),
        (["⌘", "1-9"], "Jump to a tab · ⇧⌘[ and ⇧⌘] step through them"),
        (["⌘", "Z"], "Undo"),
        (["⇧", "⌘", "C"], "Copy the list as Markdown"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(spacing: 2) {
                        ForEach(row.keys, id: \.self) { k in
                            Text(k)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .frame(minWidth: 18)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .frame(width: 78, alignment: .trailing)
                    Text(row.what)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }
}
