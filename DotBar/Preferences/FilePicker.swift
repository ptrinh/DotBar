import AppKit

enum FilePicker {
    /// Asks for a file and returns a shell command that runs it.
    /// Executable file → quoted path. Otherwise → `/bin/zsh "path"`.
    static func chooseScriptCommand() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Choose a script to run"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let path = url.path
        let quoted = "\"" + path.replacingOccurrences(of: "\\", with: "\\\\")
                                 .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        return FileManager.default.isExecutableFile(atPath: path) ? quoted : "/bin/zsh " + quoted
    }
}
