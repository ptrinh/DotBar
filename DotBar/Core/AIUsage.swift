import Foundation

/// Claude / Codex session (5 h) and weekly usage, as DotBar JSON output for the two-bar
/// `usage:` symbol. Runs in-process for `dotbar usage <provider>` (see ScriptRunner), so it
/// also works in the sandboxed App Store build, where a child shell cannot read other apps'
/// sign-ins.
///
/// Sign-ins are read-only and never refreshed here: refreshing would rotate the owning CLI's
/// tokens and sign it out. When a token has expired, the menu says to run the CLI once.
enum AIUsage {
    enum Provider: String, CaseIterable { case claude, codex }

    /// UserDefaults key for the security-scoped bookmark to ~/.codex/auth.json (sandbox only).
    static let codexBookmarkKey = "codexAuthBookmark"
    static let grantCodexURL = "dotbar://grant?what=codex"
    /// Security-scoped bookmark to ~/.claude (sandbox only): DotBar installs a Claude Code hook
    /// there and reads the usage file the hook writes.
    static let claudeDirBookmarkKey = "claudeDirBookmark"
    static let grantClaudeURL = "dotbar://grant?what=claude"
    static let claudeUsageFile = "dotbar-usage.json"
    static let claudeHookFile = "dotbar-usage-hook.sh"

    static func output(for name: String) -> String {
        guard let p = Provider(rawValue: name.lowercased()) else {
            return notice("usage:0:0", "Unknown provider \"\(name)\" (claude or codex)")
        }
        switch p {
        case .claude: return claude()
        case .codex: return codex()
        }
    }

    // MARK: Claude

    private static func claude() -> String {
        let sym = "usage:0:0:Claude"
        if Recipes.isSandboxed { return claudeFromHookFile(sym) }
        guard let token = claudeToken() else { return notice(sym, "Sign in to Claude Code to see usage") }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 8)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let j = fetch(req),
              let s = number(j, "five_hour", "utilization"), let w = number(j, "seven_day", "utilization") else {
            return notice(sym, "Usage unavailable — open Claude Code to refresh the sign-in")
        }
        let sessionLeft = (string(j, "five_hour", "resets_at").flatMap(isoDate)).map { $0.timeIntervalSinceNow }
        let weekly = string(j, "seven_day", "resets_at").flatMap(isoDate)
        return report("Claude", s, w, sessionLeft, weekly, page: "https://claude.ai/settings/usage")
    }

    /// Sandbox: the Keychain item is out of reach, so a Claude Code `Stop` hook (installed once,
    /// see installClaudeHook) saves the usage response to ~/.claude/dotbar-usage.json.
    private static func claudeFromHookFile(_ sym: String) -> String {
        guard let bookmark = UserDefaults.standard.data(forKey: claudeDirBookmarkKey) else {
            return notice(sym, "Set up Claude usage (one-time)… | href=\(grantClaudeURL)", enabled: true)
        }
        guard let dir = resolve(bookmark, key: claudeDirBookmarkKey) else {
            return notice(sym, "Allow access to ~/.claude again… | href=\(grantClaudeURL)", enabled: true)
        }
        defer { dir.stopAccessingSecurityScopedResource() }
        let file = dir.appendingPathComponent(claudeUsageFile)
        guard let data = try? Data(contentsOf: file),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let s = number(j, "five_hour", "utilization"), let w = number(j, "seven_day", "utilization") else {
            return notice(sym, "Waiting for Claude Code — usage updates after its next reply")
        }
        let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { -$0.timeIntervalSinceNow }
        let sessionLeft = (string(j, "five_hour", "resets_at").flatMap(isoDate)).map { $0.timeIntervalSinceNow }
        let weekly = string(j, "seven_day", "resets_at").flatMap(isoDate)
        return report("Claude", s, w, sessionLeft, weekly, page: "https://claude.ai/settings/usage",
                      note: age.map { "Updated \(ago($0)) by Claude Code | disabled=true" })
    }

    /// Hook script: runs inside Claude Code (outside any sandbox) after each reply, at most every
    /// 2 minutes, in the background so Claude Code never waits. The token stays in Claude Code;
    /// only the usage response is written.
    static let claudeHookScript = """
    #!/bin/sh
    # Written by DotBar: saves Claude usage for the DotBar menu bar icon. Safe to delete
    # (then remove the matching "Stop" hook from ~/.claude/settings.json).
    out="$HOME/.claude/\(claudeUsageFile)"
    [ -n "$(find "$out" -mmin -2 2>/dev/null)" ] && exit 0
    (
      c=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || cat "$HOME/.claude/.credentials.json" 2>/dev/null)
      t=$(printf %s "$c" | plutil -extract claudeAiOauth.accessToken raw -o - - 2>/dev/null)
      [ -n "$t" ] || exit 0
      curl -s --max-time 8 https://api.anthropic.com/api/oauth/usage \\
        -H "Authorization: Bearer $t" -H "anthropic-beta: oauth-2025-04-20" -o "$out.tmp" \\
        && grep -q five_hour "$out.tmp" && mv "$out.tmp" "$out"
      rm -f "$out.tmp"
    ) >/dev/null 2>&1 &
    exit 0

    """

    /// Writes the hook script into the granted ~/.claude and adds it to settings.json's `Stop`
    /// hooks (once; the previous settings.json is kept as settings.json.dotbar-bak).
    static func installClaudeHook(in dir: URL) throws {
        let fm = FileManager.default
        let script = dir.appendingPathComponent(claudeHookFile)
        try claudeHookScript.write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let settingsURL = dir.appendingPathComponent("settings.json")
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL) {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "DotBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "~/.claude/settings.json is not a JSON object"])
            }
            settings = obj
            let backup = dir.appendingPathComponent("settings.json.dotbar-bak")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: settingsURL, to: backup)
        }
        let command = "sh ~/.claude/\(claudeHookFile)"
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var stop = hooks["Stop"] as? [[String: Any]] ?? []
        let installed = stop.contains { group in
            (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(claudeHookFile) == true }
        }
        guard !installed else { return }
        stop.append(["hooks": [["type": "command", "command": command]]])
        hooks["Stop"] = stop
        settings["hooks"] = hooks
        let out = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let perms = (try? fm.attributesOfItem(atPath: settingsURL.path))?[.posixPermissions]
        try out.write(to: settingsURL, options: .atomic)
        if let perms { try? fm.setAttributes([.posixPermissions: perms], ofItemAtPath: settingsURL.path) }
    }

    /// Keychain via the `security` tool (it is on the item's access list, so no prompt), then
    /// the credentials file Claude Code writes on some setups.
    private static func claudeToken() -> String? {
        let out = ScriptRunner.runSync(#"security find-generic-password -s "Claude Code-credentials" -w"#, timeout: 5)
        var data = out.failed ? nil : Data(out.raw.utf8)
        if data == nil {
            data = try? Data(contentsOf: realHome.appendingPathComponent(".claude/.credentials.json"))
        }
        guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any] else { return nil }
        return oauth["accessToken"] as? String
    }

    // MARK: Codex

    private static func codex() -> String {
        let sym = "usage:0:0:Codex"
        let auth: Data?
        if Recipes.isSandboxed {
            guard let bookmark = UserDefaults.standard.data(forKey: codexBookmarkKey) else {
                return notice(sym, "Allow access to ~/.codex/auth.json… | href=\(grantCodexURL)", enabled: true)
            }
            // A bookmark that no longer resolves (file moved, app re-signed) needs a new grant,
            // which is not the same problem as being signed out.
            guard let (url, data) = readBookmarked(bookmark) else {
                return notice(sym, "Allow access to ~/.codex/auth.json again… | href=\(grantCodexURL)", enabled: true)
            }
            guard codexToken(in: data) != nil || url.lastPathComponent == "auth.json" else {
                return notice(sym, "\(url.lastPathComponent) isn't Codex's auth.json — choose again… | href=\(grantCodexURL)", enabled: true)
            }
            auth = data
        } else {
            auth = try? Data(contentsOf: realHome.appendingPathComponent(".codex/auth.json"))
        }
        guard let auth, let (token, account) = codexToken(in: auth) else {
            return notice(sym, "Sign in to Codex CLI to see usage")
        }
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, timeoutInterval: 8)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let account { req.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        req.setValue("codex_cli_rs", forHTTPHeaderField: "User-Agent")
        guard let j = fetch(req),
              let s = number(j, "rate_limit", "primary_window", "used_percent"),
              let w = number(j, "rate_limit", "secondary_window", "used_percent") else {
            return notice(sym, "Usage unavailable — run codex once to refresh the sign-in")
        }
        let sessionLeft = number(j, "rate_limit", "primary_window", "reset_after_seconds")
        let weekly = number(j, "rate_limit", "secondary_window", "reset_at").map { Date(timeIntervalSince1970: $0) }
        return report("Codex", s, w, sessionLeft, weekly, page: "https://chatgpt.com/codex/settings/usage")
    }

    /// Access token and account id from Codex CLI's auth.json (ChatGPT sign-in).
    private static func codexToken(in data: Data) -> (String, String?)? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = obj["tokens"] as? [String: Any], let token = tokens["access_token"] as? String else { return nil }
        return (token, tokens["account_id"] as? String)
    }

    private static func readBookmarked(_ bookmark: Data) -> (URL, Data)? {
        guard let url = resolve(bookmark, key: codexBookmarkKey) else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (url, data)
    }

    /// Resolves a security-scoped bookmark and starts access (caller stops it); refreshes a
    /// stale bookmark in place.
    private static func resolve(_ bookmark: Data, key: String) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: key)
        }
        return url
    }

    // MARK: Output

    private static func report(_ label: String, _ session: Double, _ weekly: Double,
                               _ sessionLeft: TimeInterval?, _ weeklyReset: Date?, page: String,
                               note: String? = nil) -> String {
        var menu = ["Session \(pct(session))  ·  resets in \(duration(sessionLeft))",
                    "Weekly \(pct(weekly))  ·  resets \(weeklyReset.map(weekday) ?? "—")"]
        if let note { menu.append(note) }
        menu += ["---", "Open usage page | href=\(page)"]
        return json(["text": "", "symbol": "usage:\(Int(session.rounded())):\(Int(weekly.rounded())):\(label)", "menu": menu])
    }

    private static func notice(_ symbol: String, _ line: String, enabled: Bool = false) -> String {
        json(["text": "", "symbol": symbol, "menu": [enabled ? line : "\(line) | disabled=true"]])
    }

    private static func ago(_ s: TimeInterval) -> String {
        let m = Int(s) / 60
        return m < 1 ? "just now" : m < 60 ? "\(m) min ago" : "\(m / 60)h \(m % 60)m ago"
    }

    private static func pct(_ v: Double) -> String { "\(Int(v.rounded()))%" }

    private static func duration(_ s: TimeInterval?) -> String {
        guard let s else { return "—" }
        let m = max(0, Int(s) / 60)
        return String(format: "%dh %02dm", m / 60, m % 60)
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE HH:mm"; return f
    }()
    private static func weekday(_ d: Date) -> String { weekdayFormatter.string(from: d) }

    private static func isoDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    // MARK: Plumbing

    /// Blocking fetch on the caller's (background) thread; nil on any HTTP or JSON error.
    private static func fetch(_ req: URLRequest) -> [String: Any]? {
        let done = DispatchSemaphore(value: 0)
        var result: [String: Any]?
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            if (resp as? HTTPURLResponse)?.statusCode == 200, let data {
                result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + req.timeoutInterval + 1)
        return result
    }

    private static func value(_ j: [String: Any], _ path: [String]) -> Any? {
        var cur: Any? = j
        for k in path { cur = (cur as? [String: Any])?[k] }
        return cur
    }
    private static func number(_ j: [String: Any], _ path: String...) -> Double? { (value(j, path) as? NSNumber)?.doubleValue }
    private static func string(_ j: [String: Any], _ path: String...) -> String? { value(j, path) as? String }

    private static func json(_ obj: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The user's real home even inside the sandbox (where NSHomeDirectory is the container).
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return URL(fileURLWithPath: String(cString: dir)) }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
