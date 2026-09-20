import Foundation

/// One long-lived process per streaming item (SwiftBar "streamable" plugins).
///
/// stdout is read incrementally and split on newlines. A line that is exactly `~~~` ends an
/// output block, which is delivered as one `ScriptOutput`. A script that never prints `~~~`
/// still works: until the first separator shows up, every line is its own block, so
/// `while true; do date; sleep 1; done` updates once per second.
///
/// If the process exits on its own it is restarted with exponential backoff (2s, 4s … 60s).
/// `stop()` (item disabled/removed, sleep, quit) cancels any pending restart.
final class StreamRunner {
    let command: String

    private let env: [String: String]
    private let onOutput: (ScriptOutput) -> Void
    /// Serializes all mutable state; the readability handler hops onto it.
    private let queue = DispatchQueue(label: "com.ptrinh.DotBar.stream", qos: .utility)

    private var process: Process?
    private var pipe: Pipe?
    private var buffer = Data()
    private var pending: [String] = []
    /// Set once the script prints its first `~~~`; before that each line is a block of its own.
    private var usesSeparator = false
    private var backoff: TimeInterval = 0
    private var stopped = true
    private var restartWork: DispatchWorkItem?

    private static let separator = "~~~"
    private static let maxBackoff: TimeInterval = 60

    /// `onOutput` is called on the main queue.
    init(command: String, env: [String: String] = [:], onOutput: @escaping (ScriptOutput) -> Void) {
        self.command = command
        self.env = env
        self.onOutput = onOutput
    }

    deinit { terminateProcess() }

    // MARK: - Lifecycle

    func start() {
        queue.async { [self] in
            guard stopped else { return }
            stopped = false
            backoff = 0
            launch()
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            restartWork?.cancel(); restartWork = nil
            terminateProcess()
        }
    }

    /// Manual "Refresh": kill the current process and start over immediately.
    func restart() {
        queue.async { [self] in
            restartWork?.cancel(); restartWork = nil
            stopped = true
            terminateProcess()
            stopped = false
            backoff = 0
            buffer.removeAll(); pending.removeAll(); usesSeparator = false
            launch()
        }
    }

    // MARK: - Process

    private func launch() {
        guard !stopped else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", command]
        p.environment = ScriptEnvironment.merged(env)
        p.standardInput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty { handle.readabilityHandler = nil; return }   // EOF
            self.queue.async { self.consume(data) }
        }
        p.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.processExited() }
        }

        do { try p.run() } catch {
            deliver(.parse("", failed: true, error: error.localizedDescription))
            scheduleRestart()
            return
        }
        // Own process group, so terminating kills the whole pipeline instead of orphaning it.
        _ = setpgid(p.processIdentifier, p.processIdentifier)
        process = p
        pipe = out
    }

    private func terminateProcess() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        if let p = process {
            p.terminationHandler = nil
            if p.isRunning {
                let pid = p.processIdentifier
                if getpgid(pid) == pid { kill(-pid, SIGTERM) } else { p.terminate() }
            }
        }
        process = nil
        pipe = nil
    }

    private func processExited() {
        guard !stopped else { return }
        flushPending()
        process = nil
        pipe = nil
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard !stopped else { return }
        backoff = backoff == 0 ? 2 : min(backoff * 2, Self.maxBackoff)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restartWork = nil
            self.launch()
        }
        restartWork = work
        queue.asyncAfter(deadline: .now() + backoff, execute: work)
    }

    // MARK: - Parsing

    private func consume(_ data: Data) {
        buffer.append(data)
        while let idx = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<idx]
            buffer.removeSubrange(buffer.startIndex...idx)
            handle(line: String(decoding: lineData, as: UTF8.self))
        }
        // Guard against a script that never prints a newline.
        if buffer.count > 1 << 20 { buffer.removeAll() }
    }

    private func handle(line raw: String) {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        if line.trimmingCharacters(in: .whitespaces) == Self.separator {
            usesSeparator = true
            flushPending()
            return
        }
        pending.append(line)
        if !usesSeparator { flushPending() }   // line-per-update mode
    }

    private func flushPending() {
        let block = pending.joined(separator: "\n")
        pending.removeAll()
        guard !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        backoff = 0   // the script produced something, so it is healthy
        deliver(.parse(block))
    }

    private func deliver(_ out: ScriptOutput) {
        DispatchQueue.main.async { [onOutput] in onOutput(out) }
    }
}
