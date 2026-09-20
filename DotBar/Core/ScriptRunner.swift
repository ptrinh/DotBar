import Foundation

enum ScriptRunner {
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
