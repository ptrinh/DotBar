import AppKit

/// `dotbar://` URL scheme, so scripts and other apps can drive DotBar:
///
///     dotbar://refresh
///     dotbar://refresh?name=CPU%20Load        (or ?id=<uuid>)
///     dotbar://set?name=Build&text=passing
///     dotbar://enable?name=Build&value=false
///     dotbar://prefs
///
/// Names match case-insensitively.
@MainActor
enum URLCommands {
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "dotbar" else { return }

        // dotbar://refresh -> host; dotbar:/refresh or dotbar:refresh -> path.
        let raw = url.host?.isEmpty == false
            ? url.host!
            : url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let command = raw.lowercased()

        var query: [String: String] = [:]
        for q in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            query[q.name.lowercased()] = q.value
        }

        let state = AppState.shared
        switch command {
        case "refresh":
            if let item = item(matching: query, in: state) { state.refresh(item) }
            else if query["name"] == nil && query["id"] == nil { state.refreshAll() }
        case "set":
            guard let item = item(matching: query, in: state), let text = query["text"] else { return }
            state.applyExternalOutput(text, for: item.id)
        case "enable":
            guard var item = item(matching: query, in: state) else { return }
            item.enabled = boolValue(query["value"])
            state.update(item)
        case "prefs", "preferences":
            PreferencesWindowController.shared.show()
        default:
            break
        }
    }

    private static func item(matching query: [String: String], in state: AppState) -> Item? {
        if let idString = query["id"], let id = UUID(uuidString: idString) {
            return state.items.first { $0.id == id }
        }
        if let name = query["name"] {
            let wanted = name.lowercased()
            return state.items.first { $0.name.lowercased() == wanted }
        }
        return nil
    }

    private static func boolValue(_ s: String?) -> Bool {
        guard let s = s?.lowercased() else { return true }
        return !["false", "0", "no", "off"].contains(s)
    }
}
