import Foundation
import Carbon
import AppKit
import Combine

/// The subset of hotkey behaviour used to cancel a capture before any overlay exists.
@MainActor
public protocol TemporaryEscapeHandling: AnyObject {
    @discardableResult
    func registerTemporaryEscape(action: @escaping @MainActor @Sendable () -> Void) -> Bool
    func unregisterTemporaryEscape()
    var isTemporaryEscapeRegistered: Bool { get }
}

/// Owns DocShot's global shortcuts: one table keyed by `ShortcutAction`, each entry with a
/// default, an optional saved override and a handler.
public final class HotkeyService: ObservableObject, @unchecked Sendable {
    public typealias Handler = @MainActor @Sendable () -> Void

    public static let shared = HotkeyService()

    /// 'DSHT'
    fileprivate static let signature = OSType(0x44534854)

    /// Escape, registered only while a capture is pending and no overlay exists yet.
    /// The table's actions use the other identifiers; see `ShortcutAction.hotKeyID`.
    fileprivate static let temporaryEscapeID: UInt32 = 2

    private let store: ShortcutStore
    private var hotKeyRefs: [ShortcutAction: EventHotKeyRef] = [:]
    private var handlers: [ShortcutAction: Handler] = [:]
    private var escapeHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onTemporaryEscape: Handler?

    /// The binding in force for every action, default or override.
    @Published public private(set) var bindings: [ShortcutAction: ShortcutBinding] = [:]
    /// The most recent registration failure, or nil once a registration succeeds.
    @Published public private(set) var lastError: String?

    public var registrationFailed: Bool { lastError != nil }

    /// The screenshot binding. Kept under this name for existing callers.
    public var currentPreset: ShortcutBinding { binding(for: .screenshot) }

    /// `shared` is the app's instance. A separate instance over a scratch store exists only
    /// so tests can exercise real registration without touching the saved preferences.
    init(store: ShortcutStore = ShortcutStore()) {
        self.store = store
        store.migrateLegacyIfNeeded()
        for action in ShortcutAction.allCases {
            bindings[action] = store.binding(for: action)
        }
    }

    public func binding(for action: ShortcutAction) -> ShortcutBinding {
        bindings[action] ?? action.defaultBinding
    }

    public func isUsingDefault(_ action: ShortcutAction) -> Bool {
        binding(for: action) == action.defaultBinding
    }

    /// Registers the action's current binding with the system and remembers the handler, so
    /// later rebinding does not need the caller to supply it again.
    @discardableResult
    public func register(_ action: ShortcutAction, handler: @escaping Handler) -> Bool {
        handlers[action] = handler
        guard action.isRegistrable else { return false }
        return activate(binding(for: action), for: action)
    }

    /// Rebinds an action. The new chord is saved only if the system accepts it; on failure
    /// the previous binding is put back so the action is never left without a shortcut.
    @discardableResult
    public func setBinding(_ binding: ShortcutBinding, for action: ShortcutAction) -> Bool {
        let previous = self.binding(for: action)

        if let clash = ShortcutAction.allCases.first(where: {
            $0 != action && self.binding(for: $0).isSameChord(as: binding)
        }) {
            lastError = "\(binding.shortcutDisplay) is already used by \(clash.title)."
            return false
        }

        if action.isRegistrable, handlers[action] != nil {
            guard activate(binding, for: action) else {
                let failure = lastError
                activate(previous, for: action)
                lastError = failure
                return false
            }
        }

        if binding == action.defaultBinding {
            store.clearOverride(for: action)
        } else {
            store.setOverride(binding, for: action)
        }
        bindings[action] = binding
        return true
    }

    @discardableResult
    public func resetToDefault(_ action: ShortcutAction) -> Bool {
        setBinding(action.defaultBinding, for: action)
    }

    public func unregister(_ action: ShortcutAction) {
        if let ref = hotKeyRefs.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
        handlers[action] = nil
        removeEventHandlerIfUnused()
    }

    @discardableResult
    private func activate(_ binding: ShortcutBinding, for action: ShortcutAction) -> Bool {
        if let ref = hotKeyRefs.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }

        guard installEventHandlerIfNeeded() else {
            lastError = lastError ?? "Failed to install Carbon event handler."
            return false
        }

        let hotKeyID = EventHotKeyID(signature: HotkeyService.signature, id: action.hotKeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            lastError = "\(action.title) shortcut \(binding.shortcutDisplay) failed to register (OSStatus \(status)). Key combo may be in use."
            removeEventHandlerIfUnused()
            return false
        }

        hotKeyRefs[action] = ref
        lastError = nil
        return true
    }

    /// Installs the shared Carbon handler once. Every table action and the temporary Escape
    /// registration dispatch through it, so none can tear down another's delivery.
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
                    if identifier == HotkeyService.temporaryEscapeID {
                        service.onTemporaryEscape?()
                    } else if let action = ShortcutAction.allCases.first(where: { $0.hotKeyID == identifier }) {
                        service.handlers[action]?()
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

    /// Removes the shared handler only once nothing is registered through it.
    private func removeEventHandlerIfUnused() {
        guard hotKeyRefs.isEmpty, escapeHotKeyRef == nil,
              let handler = eventHandlerRef else { return }
        RemoveEventHandler(handler)
        eventHandlerRef = nil
    }

    deinit {
        if let ref = escapeHotKeyRef {
            UnregisterEventHotKey(ref)
            escapeHotKeyRef = nil
        }
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        removeEventHandlerIfUnused()
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
        hotKeyID.id = HotkeyService.temporaryEscapeID

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
