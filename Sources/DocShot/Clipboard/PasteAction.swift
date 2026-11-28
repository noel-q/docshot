import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// What Return or a click does with the chosen item (C3 plan, decisions 1 and 2).
enum PasteOutcome: Equatable {
    /// Copy, close, bring the previous app back and press Cmd+V there.
    case pasteIntoPreviousApp
    /// Copy and close; the user presses Cmd+V. `askForAccess` shows the system's
    /// Accessibility request, which happens once at most.
    case copyOnly(askForAccess: Bool)
}

enum PastePlanner {
    static func outcome(
        pasteDirectly: Bool, accessAllowed: Bool, hasPreviousApp: Bool, accessRequestedBefore: Bool
    ) -> PasteOutcome {
        guard pasteDirectly else { return .copyOnly(askForAccess: false) }
        guard accessAllowed else { return .copyOnly(askForAccess: !accessRequestedBefore) }
        return hasPreviousApp ? .pasteIntoPreviousApp : .copyOnly(askForAccess: false)
    }
}

/// Accessibility permission, which sending Cmd+V to another app needs (plan 4.4).
enum AccessibilityAccess {
    static var isAllowed: Bool { AXIsProcessTrusted() }

    /// Shows the system's request. macOS shows it only while DocShot is not yet in the list.
    static func request() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Sends Cmd+V to the front app. Keyboard layout calls must run on the main thread, so the
/// whole type is main-actor bound.
@MainActor
enum PasteKeystroke {
    static let ansiV = CGKeyCode(kVK_ANSI_V)

    /// The key that gives "v" with Command held in the current keyboard layout, so layouts such
    /// as Dvorak paste too. Falls back to the ANSI V key.
    static func keyCodeForV() -> CGKeyCode {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let data = layoutData(of: source) else { return ansiV }
        return keyCode(for: "v", layoutData: data) ?? ansiV
    }

    static func layoutData(of source: TISInputSource) -> Data? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    }

    /// The first key code (0 to 127) that types `character` with Command held, or nil.
    static func keyCode(for character: Character, layoutData: Data) -> CGKeyCode? {
        let wanted = String(character)
        return layoutData.withUnsafeBytes { buffer -> CGKeyCode? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            let commandState = UInt32((cmdKey >> 8) & 0xFF)
            for code in 0..<128 {
                var deadKeyState: UInt32 = 0
                var characters = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDown), commandState, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
                )
                if status == noErr, length == 1,
                   String(utf16CodeUnits: characters, count: 1).lowercased() == wanted {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }

    /// Command as a real keyboard sends it: the Command flag plus the device bit for the left
    /// Command key (NX_DEVICELCMDKEYMASK), as a real keyboard sends it. Without it Cmd+V did
    /// not reach the Claude app (Electron) on 24 November 2026; TextEdit accepts either.
    static let commandFlags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x0000_0008)

    /// Posts Cmd+V. Needs Accessibility; without it macOS drops the events.
    @discardableResult
    static func postCommandV() -> Bool {
        let key = keyCodeForV()
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            return false
        }
        down.flags = commandFlags
        up.flags = commandFlags
        // Session tap with the device bit, as widely used clipboard managers post it (assumed
        // to suit Chromium apps; TextEdit verified 24 November 2026).
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }

    /// Waits until `app` reports a focused element through Accessibility, up to `timeout`.
    /// False if it never did (some apps expose none); the paste then goes ahead after the wait.
    static func waitForFocusedElement(in app: NSRunningApplication, timeout: Duration = .milliseconds(400)) async -> Bool {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // Each query blocks the main thread; a hung app must not freeze DocShot for the
        // default six seconds.
        AXUIElementSetMessagingTimeout(element, 0.1)
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            var focused: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
               focused != nil {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    /// Waits until `app` is the front app, up to `timeout`. False if it never got there.
    static func waitUntilFrontmost(_ app: NSRunningApplication, timeout: Duration = .seconds(1)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}
