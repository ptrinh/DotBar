import AppKit
import UserNotifications

/// Thin wrapper around UserNotifications. Authorization is requested lazily, the
/// first time an item actually wants a notification.
enum Notifier {
    private static var didRequest = false
    private static var authorized = false

    /// Ask for permission once, the first time it is needed.
    static func requestAuthorizationIfNeeded() {
        guard !didRequest else { return }
        didRequest = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("DotBar: notification auth failed: \(error)") }
            authorized = granted
        }
    }

    static func post(title: String, body: String) {
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            if let error { NSLog("DotBar: notification post failed: \(error)") }
        }
    }

    // MARK: Color naming

    private static let palette: [(name: String, r: CGFloat, g: CGFloat, b: CGFloat)] = [
        ("red",    1.00, 0.27, 0.23),
        ("orange", 1.00, 0.62, 0.04),
        ("yellow", 1.00, 0.84, 0.04),
        ("green",  0.20, 0.78, 0.35),
        ("blue",   0.04, 0.52, 1.00),
        ("purple", 0.75, 0.35, 0.95),
        ("gray",   0.56, 0.56, 0.58),
    ]

    /// Nearest human name for a color, or its hex when nothing is close.
    static func name(for color: NSColor) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return color.hexString }
        var best: (String, CGFloat) = ("", .greatestFiniteMagnitude)
        for p in palette {
            let d = (c.redComponent - p.r) * (c.redComponent - p.r)
                  + (c.greenComponent - p.g) * (c.greenComponent - p.g)
                  + (c.blueComponent - p.b) * (c.blueComponent - p.b)
            if d < best.1 { best = (p.name, d) }
        }
        return best.1 <= 0.09 ? best.0 : c.hexString   // 0.09 ≈ 0.3 distance in RGB unit cube
    }
}
