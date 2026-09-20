import Foundation

/// The environment every DotBar child process runs with — shared by ScriptRunner and StreamRunner.
enum ScriptEnvironment {
    /// PATH resolved once from the user's login shell, so each run can use a cheap non-login shell.
    static let base: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "print -rn -- $PATH"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            env["PATH"] = path.isEmpty ? fallback : path + ":" + fallback
        } else { env["PATH"] = fallback }
        return env
    }()

    /// `extra` (the DOTBAR_* variables) merged on top of the base environment.
    static func merged(_ extra: [String: String]) -> [String: String] {
        guard !extra.isEmpty else { return base }
        var env = base
        for (k, v) in extra { env[k] = v }
        return env
    }
}
