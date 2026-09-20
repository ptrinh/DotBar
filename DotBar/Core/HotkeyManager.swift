import AppKit
import Carbon.HIToolbox

/// Minimal Carbon global-hotkey registry. One process-wide event handler,
/// one Carbon registration per key, closures keyed by an integer id.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private struct Entry {
        var ref: EventHotKeyRef?
        var handler: () -> Void
    }

    private var entries: [UInt32: Entry] = [:]
    private var keys: [UUID: UInt32] = [:]        // owner -> carbon id
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Register (or replace) the hotkey owned by `owner`. Passing nil unregisters.
    func set(_ hotkey: Hotkey?, for owner: UUID, handler: @escaping () -> Void) {
        unregister(owner: owner)
        guard let hotkey, hotkey.modifiers != 0 else { return }
        installHandlerIfNeeded()
        let id = nextID
        nextID &+= 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x44_54_42_52), id: id)   // 'DTBR'
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            NSLog("DotBar: RegisterEventHotKey failed (\(status)) for \(hotkey.display)")
            return
        }
        entries[id] = Entry(ref: ref, handler: handler)
        keys[owner] = id
    }

    func unregister(owner: UUID) {
        guard let id = keys.removeValue(forKey: owner), let entry = entries.removeValue(forKey: id) else { return }
        if let ref = entry.ref { UnregisterEventHotKey(ref) }
    }

    fileprivate func fire(_ id: UInt32) { entries[id]?.handler() }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler, 1, &spec, nil, &handlerRef)
    }
}

/// Carbon callback — runs on the main run loop.
private func hotkeyEventHandler(_ callRef: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let id = hotKeyID.id
    MainActor.assumeIsolated { HotkeyManager.shared.fire(id) }
    return noErr
}

// MARK: - Display & key names

extension Hotkey {
    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + Hotkey.keyName(keyCode)
    }

    /// Cocoa modifier flags -> Carbon modifier flags.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    static func keyName(_ code: UInt32) -> String {
        if let n = named[code] { return n }
        return "Key \(code)"
    }

    private static let named: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1",
        115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
