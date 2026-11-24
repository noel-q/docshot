import Foundation
import Carbon

/// The global shortcuts DocShot owns. The rule is three, no more: everything else is a menu
/// item or a key inside a window.
public enum ShortcutAction: String, CaseIterable, Identifiable, Sendable {
    case screenshot
    case record
    case openWindow

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .record: return "Record (start or stop)"
        case .openWindow: return "Open DocShot window"
        }
    }

    /// Every action is registered with the system. `openWindow` was held back until the window
    /// it opens existed; that window arrived in C2.
    public var isRegistrable: Bool {
        switch self {
        case .screenshot, .record, .openWindow: return true
        }
    }

    /// Carbon hotkey identifier. 2 is reserved for the temporary Escape registration.
    public var hotKeyID: UInt32 {
        switch self {
        case .screenshot: return 1
        case .record: return 3
        case .openWindow: return 4
        }
    }

    public var defaultBinding: ShortcutBinding {
        let family = UInt32(controlKey | optionKey | cmdKey)
        switch self {
        case .screenshot:
            return ShortcutBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: family, keyDisplay: "S")
        case .record:
            return ShortcutBinding(keyCode: UInt32(kVK_ANSI_R), modifiers: family, keyDisplay: "R")
        case .openWindow:
            return ShortcutBinding(keyCode: UInt32(kVK_ANSI_V), modifiers: family, keyDisplay: "V")
        }
    }
}

/// One key chord, in Carbon key code and modifier terms.
public struct ShortcutBinding: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let keyDisplay: String

    public init(keyCode: UInt32, modifiers: UInt32, keyDisplay: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyDisplay = keyDisplay
    }

    /// For example "⌃⌥⌘S".
    public var shortcutDisplay: String {
        HotkeyDisplay.shortcut(modifiers: modifiers, keyDisplay: keyDisplay)
    }

    /// Two bindings collide when they are the same chord, whatever label was saved with them.
    public func isSameChord(as other: ShortcutBinding) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }
}

public enum HotkeyDisplay {
    public static func shortcut(modifiers: UInt32, keyDisplay: String) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyDisplay.uppercased()
    }
}

/// Saved overrides for the shortcut table, plus the one-time migration from the single
/// configurable screenshot slot that preceded it. Pure storage: it never touches Carbon.
public struct ShortcutStore {
    public static let migrationVersionKey = "DocShotShortcutMigrationVersion"
    public static let currentMigrationVersion = 1

    enum LegacyKey {
        static let presetID = "DocShotHotkeyPresetID"
        static let customEnabled = "DocShotCustomHotkeyEnabled"
        static let customKeyCode = "DocShotCustomHotkeyKeyCode"
        static let customModifiers = "DocShotCustomHotkeyModifiers"
        static let customKeyDisplay = "DocShotCustomHotkeyKeyDisplay"

        static let all = [presetID, customEnabled, customKeyCode, customModifiers, customKeyDisplay]
    }

    /// The removed preset list, kept only so a saved choice survives as a custom binding.
    /// Preset 0 (Cmd+Shift+6) is absent on purpose: launch always wrote a preset ID, so a
    /// saved 0 cannot be told apart from "never chose", and it moves to the new default.
    static let legacyPresets: [Int: ShortcutBinding] = [
        1: ShortcutBinding(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey), keyDisplay: "5"),
        2: ShortcutBinding(keyCode: UInt32(kVK_ANSI_7), modifiers: UInt32(cmdKey | shiftKey), keyDisplay: "7"),
        3: ShortcutBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey | shiftKey), keyDisplay: "S")
    ]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ action: ShortcutAction, _ field: String) -> String {
        "DocShotShortcut.\(action.rawValue).\(field)"
    }

    /// The saved override, or nil when the action uses its default.
    public func override(for action: ShortcutAction) -> ShortcutBinding? {
        guard let keyCode = defaults.object(forKey: key(action, "keyCode")) as? Int,
              let modifiers = defaults.object(forKey: key(action, "modifiers")) as? Int,
              keyCode >= 0, modifiers >= 0 else {
            return nil
        }
        let display = defaults.string(forKey: key(action, "keyDisplay")) ?? "?"
        return ShortcutBinding(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers), keyDisplay: display)
    }

    /// The binding in force: the saved override if there is one, otherwise the default.
    public func binding(for action: ShortcutAction) -> ShortcutBinding {
        override(for: action) ?? action.defaultBinding
    }

    public func setOverride(_ binding: ShortcutBinding, for action: ShortcutAction) {
        defaults.set(Int(binding.keyCode), forKey: key(action, "keyCode"))
        defaults.set(Int(binding.modifiers), forKey: key(action, "modifiers"))
        defaults.set(binding.keyDisplay, forKey: key(action, "keyDisplay"))
    }

    public func clearOverride(for action: ShortcutAction) {
        for field in ["keyCode", "modifiers", "keyDisplay"] {
            defaults.removeObject(forKey: key(action, field))
        }
    }

    /// Runs once. A saved custom screenshot shortcut is kept; a saved preset other than the
    /// old default becomes a custom binding; recording never had a saved value, so it simply
    /// takes the new default.
    public func migrateLegacyIfNeeded() {
        guard defaults.integer(forKey: Self.migrationVersionKey) < Self.currentMigrationVersion else {
            return
        }

        if defaults.bool(forKey: LegacyKey.customEnabled) {
            let keyCode = defaults.integer(forKey: LegacyKey.customKeyCode)
            let modifiers = defaults.integer(forKey: LegacyKey.customModifiers)
            if keyCode >= 0, modifiers > 0 {
                setOverride(
                    ShortcutBinding(
                        keyCode: UInt32(keyCode),
                        modifiers: UInt32(modifiers),
                        keyDisplay: defaults.string(forKey: LegacyKey.customKeyDisplay) ?? "?"
                    ),
                    for: .screenshot
                )
            }
        } else if let presetID = defaults.object(forKey: LegacyKey.presetID) as? Int,
                  let preset = Self.legacyPresets[presetID] {
            setOverride(preset, for: .screenshot)
        }

        LegacyKey.all.forEach(defaults.removeObject(forKey:))
        defaults.set(Self.currentMigrationVersion, forKey: Self.migrationVersionKey)
    }
}
