import SwiftUI

struct PreferencesView: View {
    @ObservedObject var state: AppState
    @ObservedObject var selection: PreferencesWindowController.SelectionModel
    @State private var showGlobalHotkey = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection.itemID) {
                ForEach(state.items) { item in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { item.enabled },
                            set: { v in var i = item; i.enabled = v; state.update(i) }
                        )).labelsHidden().toggleStyle(.checkbox)
                        VStack(alignment: .leading) {
                            Text(item.name).font(.body)
                            Text(subtitle(item)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(item.id)
                }
                .onMove { from, to in state.items.move(fromOffsets: from, toOffset: to) }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Button { selection.itemID = state.addItem().id } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selection.itemID { state.removeItem(id); selection.itemID = state.items.first?.id }
                    } label: { Image(systemName: "minus") }.disabled(selection.itemID == nil)
                    Menu {
                        ForEach(Recipes.all()) { recipe in
                            Button(recipe.name) { state.items.append(recipe); selection.itemID = recipe.id }
                        }
                    } label: { Image(systemName: "sparkles") }
                    .menuStyle(.borderlessButton).frame(width: 40)
                    .help("Add a ready-made recipe")
                    Spacer()
                    Button { showGlobalHotkey.toggle() } label: { Image(systemName: "gearshape") }
                        .popover(isPresented: $showGlobalHotkey, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Global shortcut").font(.headline)
                                HotkeyRecorder(label: "Refresh All", hotkey: Binding(
                                    get: { state.refreshAllHotkey },
                                    set: { state.refreshAllHotkey = $0 }))
                                Text("Works anywhere in macOS. At least one modifier is required.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Divider()
                                Toggle("Slow down in Low Power Mode", isOn: Binding(
                                    get: { state.respectLowPowerMode },
                                    set: { state.respectLowPowerMode = $0 }))
                                Text("Refresh intervals under a minute run 3x slower (at least 30s) while Low Power Mode is on.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(12).frame(width: 360)
                        }
                    Menu {
                        Button("Import…") { importItems() }
                        Button("Export…") { exportItems() }
                    } label: { Image(systemName: "square.and.arrow.up.on.square") }
                    .menuStyle(.borderlessButton).frame(width: 40)
                }
                .padding(8)
                .background(.bar)
            }
        } detail: {
            if let id = selection.itemID, let item = state.binding(for: id) {
                ItemEditorView(state: state, item: Binding(
                    get: { state.binding(for: id) ?? item },
                    set: { state.update($0) }
                ))
                .id(id)
            } else {
                ContentUnavailableView("Select an item", systemImage: "circle.grid.2x1", description: Text("Or press + to add one."))
            }
        }
        .onAppear { if selection.itemID == nil { selection.itemID = state.items.first?.id } }
    }

    private func subtitle(_ item: Item) -> String {
        var parts: [String] = []
        switch item.source {
        case .static: parts.append("Static")
        case .script(_, let s): parts.append(s > 0 ? "\(s)s" : "Manual")
        }
        if !item.dots.isEmpty { parts.append("\(item.dots.count) dot\(item.dots.count > 1 ? "s" : "")") }
        return parts.joined(separator: " · ")
    }

    private func exportItems() {
        let p = NSSavePanel(); p.nameFieldStringValue = "DotBar.json"; p.allowedContentTypes = [.json]
        if p.runModal() == .OK, let url = p.url { try? Store.export(state.items, to: url) }
    }

    private func importItems() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]; p.allowsMultipleSelection = false
        if p.runModal() == .OK, let url = p.url, let items = try? Store.importItems(from: url) {
            let existing = Set(state.items.map(\.id))
            state.items.append(contentsOf: items.filter { !existing.contains($0.id) })
        }
    }
}
