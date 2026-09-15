import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DocStore
    @State private var tip: String?
    @State private var showShortcuts = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ChecklistTextView(text: $store.text)
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
            if showShortcuts {
                Divider()
                ShortcutsPanel()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            footer
        }
        .frame(width: 380, height: 460)
        .animation(.easeOut(duration: 0.12), value: tip)
        .animation(.easeOut(duration: 0.18), value: showShortcuts)
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
            FooterButton("keyboard", "Keyboard shortcuts", tip: $tip, active: showShortcuts) {
                showShortcuts.toggle()
            }
            FooterButton("doc.on.doc", "Copy as Markdown  ⇧⌘C", tip: $tip) { store.copyAsMarkdown() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(store.text.isEmpty)
            FooterButton("trash", "Clear everything", tip: $tip) { store.clear() }
                .disabled(store.text.isEmpty)
            FooterButton("power", "Quit PasteList  ⌘Q", tip: $tip) { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
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

private struct ShortcutsPanel: View {
    private let rows: [(keys: [String], what: String)] = [
        (["⌘", "V"], "Paste text, exactly as copied"),
        (["⇥"], "Give this line (or every selected line) a checkbox"),
        (["⇧", "⇥"], "Take the checkbox off"),
        (["⌘", "↩"], "Tick or untick this line"),
        (["↩"], "Next item · on an empty item, drops its box"),
        (["⌫"], "Right after a box, removes the box"),
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
