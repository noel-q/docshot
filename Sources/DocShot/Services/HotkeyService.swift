import Foundation
import Carbon
import AppKit
import Combine

public struct HotkeyPreset: Identifiable, Equatable, Sendable {
    public static let customID = -1

    public let id: Int
    public let label: String
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let shortcutDisplay: String

    public init(
        id: Int,
        label: String,
        keyCode: UInt32,
        modifiers: UInt32,
        shortcutDisplay: String? = nil
    ) {
        self.id = id
        self.label = label
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.shortcutDisplay = shortcutDisplay
            ?? label.split(separator: " ", maxSplits: 1).first.map(String.init)
            ?? label
    }

    public static func custom(keyCode: UInt32, modifiers: UInt32, keyDisplay: String) -> HotkeyPreset {
        let display = HotkeyDisplay.shortcut(modifiers: modifiers, keyDisplay: keyDisplay)
        return HotkeyPreset(
            id: customID,
            label: "Custom: \(display)",
            keyCode: keyCode,
            modifiers: modifiers,
            shortcutDisplay: display
        )
    }
    
    public static let presets: [HotkeyPreset] = [
        HotkeyPreset(id: 0, label: "⌘⇧6 (Cmd + Shift + 6)", keyCode: 22, modifiers: UInt32(cmdKey | shiftKey)),
        HotkeyPreset(id: 1, label: "⌘⇧5 (Cmd + Shift + 5)", keyCode: 23, modifiers: UInt32(cmdKey | shiftKey)),
        HotkeyPreset(id: 2, label: "⌘⇧7 (Cmd + Shift + 7)", keyCode: 26, modifiers: UInt32(cmdKey | shiftKey)),
        HotkeyPreset(id: 3, label: "⌥⇧S (Option + Shift + S)", keyCode: 1, modifiers: UInt32(optionKey | shiftKey))
    ]
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

/// The subset of hotkey behaviour used to cancel a capture before any overlay exists.
@MainActor
public protocol TemporaryEscapeHandling: AnyObject {
    @discardableResult
    func registerTemporaryEscape(action: @escaping @MainActor @Sendable () -> Void) -> Bool
    func unregisterTemporaryEscape()
    var isTemporaryEscapeRegistered: Bool { get }
}

public final class HotkeyService: ObservableObject, @unchecked Sendable {
    public static let shared = HotkeyService()

    /// 'DSHT'
    fileprivate static let signature = OSType(0x44534854)

    fileprivate enum HotkeyIdentifier {
        /// The user's configurable capture shortcut.
        static let capture: UInt32 = 1
        /// Escape, registered only while a capture is pending and no overlay exists yet.
        static let temporaryEscape: UInt32 = 2
        static let recording: UInt32 = 3
    }

    private var hotKeyRef: EventHotKeyRef?
    private var escapeHotKeyRef: EventHotKeyRef?
    private var recordingHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onTrigger: (@MainActor @Sendable () -> Void)?
    private var onTemporaryEscape: (@MainActor @Sendable () -> Void)?
    private var onRecordingTrigger: (@MainActor @Sendable () -> Void)?

    private enum DefaultsKey {
        static let presetID = "DocShotHotkeyPresetID"
        static let customEnabled = "DocShotCustomHotkeyEnabled"
        static let customKeyCode = "DocShotCustomHotkeyKeyCode"
        static let customModifiers = "DocShotCustomHotkeyModifiers"
        static let customKeyDisplay = "DocShotCustomHotkeyKeyDisplay"
    }
    
    @Published public private(set) var currentPreset: HotkeyPreset = HotkeyPreset.presets[0]
    @Published public private(set) var recordingPreset = HotkeyPreset(id: 4, label: "⌘⇧8 (Cmd + Shift + 8)", keyCode: 28, modifiers: UInt32(cmdKey | shiftKey))
    public private(set) var registrationFailed: Bool = false
    public private(set) var lastError: String?
    
    private init() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: DefaultsKey.customEnabled) {
            let display = defaults.string(forKey: DefaultsKey.customKeyDisplay) ?? "?"
            self.currentPreset = .custom(
                keyCode: UInt32(defaults.integer(forKey: DefaultsKey.customKeyCode)),
                modifiers: UInt32(defaults.integer(forKey: DefaultsKey.customModifiers)),
                keyDisplay: display
            )
            return
        }

        let savedID = defaults.integer(forKey: DefaultsKey.presetID)
        if let preset = HotkeyPreset.presets.first(where: { $0.id == savedID }) {
            self.currentPreset = preset
        }
    }
    
    @discardableResult
    public func registerPreset(_ preset: HotkeyPreset, action: @escaping @MainActor @Sendable () -> Void) -> Bool {
        self.currentPreset = preset
        UserDefaults.standard.set(preset.id, forKey: DefaultsKey.presetID)
        UserDefaults.standard.set(false, forKey: DefaultsKey.customEnabled)
        return registerHotkey(keyCode: preset.keyCode, modifiers: preset.modifiers, action: action)
    }

    @discardableResult
    public func registerCustomShortcut(
        keyCode: UInt32,
        modifiers: UInt32,
        keyDisplay: String,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> Bool {
        let shortcut = HotkeyPreset.custom(
            keyCode: keyCode,
            modifiers: modifiers,
            keyDisplay: keyDisplay
        )

        guard registerHotkey(keyCode: keyCode, modifiers: modifiers, action: action) else {
            return false
        }

        currentPreset = shortcut
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: DefaultsKey.customEnabled)
        defaults.set(Int(keyCode), forKey: DefaultsKey.customKeyCode)
        defaults.set(Int(modifiers), forKey: DefaultsKey.customModifiers)
        defaults.set(keyDisplay, forKey: DefaultsKey.customKeyDisplay)
        return true
    }
    
    @discardableResult
    public func registerHotkey(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor @Sendable () -> Void) -> Bool {
        unregisterCaptureHotkey()

        self.onTrigger = action
        self.registrationFailed = false
        self.lastError = nil

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = HotkeyService.signature
        hotKeyID.id = HotkeyIdentifier.capture

        guard installEventHandlerIfNeeded() else {
            self.registrationFailed = true
            self.lastError = lastError ?? "Failed to install Carbon event handler."
            return false
        }

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            self.registrationFailed = true
            self.lastError = "Hotkey registration failed (OSStatus \(status)). Key combo may be in use."
            return false
        }

        return true
    }

    public func unregisterHotkey() {
        unregisterCaptureHotkey()
        removeEventHandlerIfUnused()
    }

    /// Releases the independently registered recording shortcut. This is primarily useful
    /// during app teardown; the recording shortcut otherwise remains active for the app's
    /// lifetime alongside the screenshot shortcut.
    public func unregisterRecordingHotkey() {
        if let ref = recordingHotKeyRef {
            UnregisterEventHotKey(ref)
            recordingHotKeyRef = nil
        }
        onRecordingTrigger = nil
        removeEventHandlerIfUnused()
    }

    @discardableResult
    public func registerRecordingHotkey(action: @escaping @MainActor @Sendable () -> Void) -> Bool {
        if let ref = recordingHotKeyRef { UnregisterEventHotKey(ref); recordingHotKeyRef = nil }
        onRecordingTrigger = action
        guard installEventHandlerIfNeeded() else { return false }
        let id = EventHotKeyID(signature: HotkeyService.signature, id: HotkeyIdentifier.recording)
        let status = RegisterEventHotKey(recordingPreset.keyCode, recordingPreset.modifiers, id, GetApplicationEventTarget(), 0, &recordingHotKeyRef)
        if status != noErr { lastError = "Recording shortcut registration failed (OSStatus \(status))."; return false }
        return true
    }

    /// Installs the shared Carbon handler once. Both the capture shortcut and the temporary
    /// Escape registration dispatch through it, so neither can tear down the other's delivery.
    private func installEventHandlerIfNeeded() -> Bool {
        if eventHandlerRef != nil { return true }

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData, let event = event else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == HotkeyService.signature else { return noErr }

                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                let identifier = hotKeyID.id
                Task { @MainActor in
                    switch identifier {
                    case HotkeyIdentifier.capture:
                        service.onTrigger?()
                    case HotkeyIdentifier.temporaryEscape:
                        service.onTemporaryEscape?()
                    case HotkeyIdentifier.recording:
                        service.onRecordingTrigger?()
                    default:
                        break
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        if handlerStatus != noErr {
            self.eventHandlerRef = nil
            self.lastError = "Failed to install Carbon event handler (OSStatus \(handlerStatus))."
            return false
        }

        return true
    }

    private func unregisterCaptureHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    /// Removes the shared handler only once nothing is registered through it.
    private func removeEventHandlerIfUnused() {
        guard hotKeyRef == nil, escapeHotKeyRef == nil, recordingHotKeyRef == nil,
              let handler = eventHandlerRef else { return }
        RemoveEventHandler(handler)
        eventHandlerRef = nil
    }

    deinit {
        if let ref = escapeHotKeyRef {
            UnregisterEventHotKey(ref)
            escapeHotKeyRef = nil
        }
        unregisterRecordingHotkey()
        unregisterHotkey()
    }
}

// MARK: - Temporary Escape

extension HotkeyService: TemporaryEscapeHandling {

    public var isTemporaryEscapeRegistered: Bool {
        escapeHotKeyRef != nil
    }

    /// Registers Escape system-wide for the short interval between starting a capture and the
    /// selection overlay appearing. Without it, Escape reaches whichever app is frontmost,
    /// because DocShot has no window to receive key events yet.
    ///
    /// This deliberately intercepts Escape for every application, so it must be released on
    /// every completion, cancellation, and error path. It never disturbs the user's capture
    /// shortcut: the two registrations use separate hotkey IDs and share one event handler.
    @discardableResult
    public func registerTemporaryEscape(action: @escaping @MainActor @Sendable () -> Void) -> Bool {
        unregisterTemporaryEscape()

        guard installEventHandlerIfNeeded() else { return false }

        self.onTemporaryEscape = action

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = HotkeyService.signature
        hotKeyID.id = HotkeyIdentifier.temporaryEscape

        let status = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &escapeHotKeyRef
        )

        if status != noErr {
            self.escapeHotKeyRef = nil
            self.onTemporaryEscape = nil
            removeEventHandlerIfUnused()
            return false
        }

        return true
    }

    /// Safe to call repeatedly and from any path, including when nothing is registered.
    public func unregisterTemporaryEscape() {
        if let ref = escapeHotKeyRef {
            UnregisterEventHotKey(ref)
            escapeHotKeyRef = nil
        }
        onTemporaryEscape = nil
        removeEventHandlerIfUnused()
    }
}
