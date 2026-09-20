import Foundation

enum ScriptRunner {
    /// PATH resolved once from the user's login shell, so each refresh runs a cheap non-login shell.
    private static let environment: [String: String] = {
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

    /// `extra` is merged on top of the base environment (DOTBAR_* variables).
    static func run(_ command: String, timeout: TimeInterval = 15, extra: [String: String] = [:]) async -> ScriptOutput {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async { cont.resume(returning: runSync(command, timeout: timeout, extra: extra)) }
        }
    }

    static func runSync(_ command: String, timeout: TimeInterval, extra: [String: String] = [:]) -> ScriptOutput {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", command]
        var env = environment
        for (k, v) in extra { env[k] = v }
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { return .parse("", failed: true, error: error.localizedDescription) }

        let group = DispatchGroup()
        var outData = Data(), errData = Data()
        group.enter(); DispatchQueue.global(qos: .utility).async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global(qos: .utility).async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return .parse("", failed: true, error: "Timed out after \(Int(timeout))s")
        }
        p.waitUntilExit()
        let stdout = String(decoding: outData, as: UTF8.self)
        let stderr = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if p.terminationStatus != 0 {
            return .parse(stdout, failed: true, error: stderr.isEmpty ? "Exit code \(p.terminationStatus)" : stderr)
        }
        return .parse(stdout)
    }
}
