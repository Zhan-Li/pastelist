import SwiftUI

@main
struct PasteListApp: App {
    @StateObject private var store = DocStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
        } label: {
            let c = store.totals
            Image(systemName: c.total > 0 && c.done == c.total ? "checklist.checked" : "checklist")
        }
        .menuBarExtraStyle(.window)
    }
}
