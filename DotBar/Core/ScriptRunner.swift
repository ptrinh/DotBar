import Foundation

enum ScriptRunner {
    /// `extra` is merged on top of the base environment (DOTBAR_* variables).
    static func run(_ command: String, timeout: TimeInterval = 15, extra: [String: String] = [:]) async -> ScriptOutput {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async { cont.resume(returning: runSync(command, timeout: timeout, extra: extra)) }
        }
    }

    static func runSync(_ command: String, timeout: TimeInterval, extra: [String: String] = [:]) -> ScriptOutput {
        // `dotbar usage <provider>` runs in-process: a child shell in the sandbox could not read
        // the sign-ins it needs, and the Homebrew build then needs no `dotbar` on PATH.
        let words = command.split(whereSeparator: \.isWhitespace)
        if words.count == 3, words[0] == "dotbar", words[1] == "usage" {
            return .parse(AIUsage.output(for: String(words[2])))
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", command]
        p.environment = ScriptEnvironment.merged(extra)
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
