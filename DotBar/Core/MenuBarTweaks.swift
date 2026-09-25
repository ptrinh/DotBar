import AppKit

/// macOS's own menu bar settings that DotBar's compact icons replace (used by onboarding).
///
/// Outside the sandbox (Homebrew build) they can be changed in one click: write the same
/// preference System Settings writes, then restart ControlCenter so the menu bar redraws. The
/// sandboxed App Store build cannot write another app's preferences, so it opens System
/// Settings → Menu Bar instead.
enum MenuBarTweaks {
    static var canApply: Bool { !Recipes.isSandboxed }

    /// Clock: date and weekday hidden (System Settings → Menu Bar → Clock Options).
    static var clockDateHidden: Bool {
        read("defaults read com.apple.menuextra.clock ShowDate") == "2"
            && read("defaults read com.apple.menuextra.clock ShowDayOfWeek") == "0"
    }

    /// The system battery icon is off the menu bar.
    static var systemBatteryHidden: Bool {
        read("defaults -currentHost read com.apple.controlcenter Battery") == "8"
    }

    @discardableResult
    static func hideClockDate() -> Bool {
        run("defaults write com.apple.menuextra.clock ShowDate -int 2; defaults write com.apple.menuextra.clock ShowDayOfWeek -bool false")
        return clockDateHidden
    }

    @discardableResult
    static func hideSystemBattery() -> Bool {
        run("defaults -currentHost write com.apple.controlcenter Battery -int 8")
        return systemBatteryHidden
    }

    static func openMenuBarSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
            NSWorkspace.shared.open(u)
        }
    }

    private static func run(_ command: String) {
        guard canApply else { return }
        _ = ScriptRunner.runSync(command + "; killall ControlCenter", timeout: 5)
    }

    private static func read(_ command: String) -> String? {
        guard canApply else { return nil }
        let out = ScriptRunner.runSync(command, timeout: 5)
        return out.failed ? nil : out.raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
