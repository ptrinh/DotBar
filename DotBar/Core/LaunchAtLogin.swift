import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    /// Register once on first launch so the app comes back after reboot. User can turn it off in the menu.
    static func enableOnFirstLaunch() {
        let key = "didOfferLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if SMAppService.mainApp.status == .notRegistered { try? SMAppService.mainApp.register() }
    }

    static func toggle() {
        do {
            if isEnabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { NSLog("DotBar: launch at login failed: \(error)") }
    }
}
