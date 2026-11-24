#if DEBUG
import AppKit
import ClipboardKit

/// Debug builds only: lets the agent drive the clipboard window from the shell, because screen
/// control cannot see or grant a menu bar app (24 November 2026). Commands arrive as the object
/// of the distributed notification `com.docshot.debug.clipboard`; after each one the state is
/// written to `<tmp>/docshot-clipboard-debug.txt`. Previews of anything that is not a test
/// item ("DocShot " prefix) are never written. Not compiled into Release builds.
@MainActor
enum ClipboardDebugHooks {
    static let notificationName = Notification.Name("com.docshot.debug.clipboard")
    static var stateFile: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("docshot-clipboard-debug.txt")
    }
    private static var observer: NSObjectProtocol?
    /// The app named by the last `open:`. A paste goes ahead only while this is both the
    /// window's paste target and the front app; anything else (another app activated
    /// meanwhile) refuses. Added after a test paste reached WhatsApp on 24 November 2026.
    private static var namedTarget: String?
    /// The only apps the hook may paste into. Chrome and Terminal are not here: the agent may
    /// not send them keystrokes by other means (their screen-control grants are read and click).
    static let testTargets: Set<String> = ["com.apple.TextEdit"]

    /// The hook listens only when DocShot was launched with `DOCSHOT_DEBUG_HOOKS=1`
    /// (`open --env DOCSHOT_DEBUG_HOOKS=1 DocShot.app`), so no other process can drive an
    /// ordinary debug run.
    static func install() {
        guard observer == nil, ProcessInfo.processInfo.environment["DOCSHOT_DEBUG_HOOKS"] == "1" else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: notificationName, object: nil, queue: .main
        ) { notification in
            let command = notification.object as? String ?? ""
            MainActor.assumeIsolated {
                run(command)
            }
        }
    }

    /// `open:<bundle id>` (only while that app is in front; it becomes the paste target),
    /// `close`, `query:<text>`, `up`, `down`, `choose`, `copy`, `pin`, `delete`,
    /// `escape`, `state`.
    static func run(_ command: String) {
        let window = ClipboardWindowController.shared
        let model = window.model
        let history = ClipboardHistoryController.shared
        switch command {
        case "open":
            return writeState("refused: name the target, open:<bundle id>")
        case "close": window.close()
        case "up": model.moveSelection(by: -1)
        case "down": model.moveSelection(by: 1)
        case "escape":
            if model.query.isEmpty { window.close() } else { model.query = "" }
        case "choose", "copy", "pin", "delete":
            Task {
                guard let item = await model.settledSelection() else { return writeState("no selection") }
                // Only test items: never pin, delete, copy or paste a real copy.
                guard item.preview.hasPrefix("DocShot ") else { return writeState("refused: not a test item") }
                // Paste only into the named target, and only while it is still in front: never
                // into whatever app the user happens to be using.
                if command == "choose" {
                    guard let named = namedTarget, window.debugPreviousApp == named,
                          NSWorkspace.shared.frontmostApplication?.bundleIdentifier == named else {
                        namedTarget = nil
                        window.close()
                        return writeState("refused: the target changed or is not in front")
                    }
                    namedTarget = nil
                }
                switch command {
                case "choose": window.choose(item)
                case "copy": window.copyOnly(item)
                case "pin": history.togglePin(item)
                default: history.delete(item)
                }
                try? await Task.sleep(for: .milliseconds(1500))
                writeState(command)
            }
            return
        default:
            if command.hasPrefix("keystroke:") {
                // Cmd+V alone, no window: only while the named app is in front.
                let bundleID = String(command.dropFirst("keystroke:".count))
                guard testTargets.contains(bundleID),
                      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
                    return writeState("refused: \(bundleID) is not an allowed test target in front")
                }
                let posted = PasteKeystroke.postCommandV()
                return writeState("keystroke posted=\(posted) at \(Date().timeIntervalSince1970)")
            }
            if command.hasPrefix("open:") {
                let bundleID = String(command.dropFirst("open:".count))
                guard testTargets.contains(bundleID),
                      let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
                      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
                    return writeState("refused: \(bundleID) is not running in front")
                }
                namedTarget = bundleID
                window.show()
                window.debugSetPreviousApp(target)
                break
            }
            if command.hasPrefix("query:") {
                model.query = String(command.dropFirst("query:".count))
                Task {
                    await model.waitForSearch()
                    writeState(command)
                }
                return
            }
        }
        writeState(command)
    }

    static func writeState(_ after: String) {
        let window = ClipboardWindowController.shared
        let model = window.model
        let history = ClipboardHistoryController.shared
        func label(_ item: ClipItem) -> String {
            let text = item.preview.hasPrefix("DocShot ") ? item.preview : "(item)"
            return "\(item.id == model.selectedID ? ">" : " ") \(item.pinned ? "[pin] " : "")\(text)"
        }
        var lines = [
            "after: \(after)",
            "showing: \(window.isShowing)",
            "query: \(model.query.isEmpty || model.query.hasPrefix("DocShot") ? model.query : "(text)")",
            "pasteDirectly: \(history.pasteDirectly) pasteAllowed: \(history.pasteAllowed)",
            "previousApp: \(window.debugPreviousApp ?? "none")",
            "front: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")",
            "lastPaste: \(window.lastPasteReport)",
            "notice: \(history.notice ?? "") problem: \(history.problem ?? "")",
            "rows:",
        ]
        lines += model.rows.map(label)
        try? lines.joined(separator: "\n").write(to: stateFile, atomically: true, encoding: .utf8)
    }
}
#endif
