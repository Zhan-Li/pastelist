import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DocStore

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ChecklistTextView(text: $store.text)
                if store.text.isEmpty {
                    Text("Paste anything here — ⌘V")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 14))
                        .padding(.horizontal, 19)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            Divider()
            footer
        }
        .frame(width: 380, height: 460)
    }

    private var footer: some View {
        let c = store.counts
        return HStack(spacing: 14) {
            Text(c.total == 0 ? "" : "\(c.done) of \(c.total) done")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            FooterButton("doc.on.doc", "Copy as Markdown") { store.copyAsMarkdown() }
                .disabled(store.text.isEmpty)
            FooterButton("trash", "Clear") { store.clear() }
                .disabled(store.text.isEmpty)
            FooterButton("power", "Quit PasteList") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct FooterButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    init(_ symbol: String, _ help: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
