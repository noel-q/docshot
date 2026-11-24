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
    /// `show`, `enable`, `disable`, `seed`, `filter:<all|text|images|files|colours>`,
    /// `select:<n>`, `snapshot:<path prefix>`, `menubar:<path prefix>`, `open-settings`,
    /// `open-onboarding`, `open-permission`, `open-thumbnail`, `open-editor`, `windows`,
    /// `theme:<ember|tide|slate|moss>`, `snapwin:<word>:<path prefix>`, `close`, `query:<text>`, `up`, `down`, `choose`, `copy`, `pin`, `delete`,
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
            if command == "show" {
                // The window without a paste target: for looking, never for pasting.
                window.show()
                break
            }
            // Commands that add or change history run only against the scratch store, never the
            // real one (`DOCSHOT_DEBUG_STORE`).
            if ["pause", "resume", "enable", "disable", "seed"].contains(command),
               (ProcessInfo.processInfo.environment["DOCSHOT_DEBUG_STORE"] ?? "").isEmpty {
                return writeState("refused: \(command) needs DOCSHOT_DEBUG_STORE")
            }
            if command == "pause" || command == "resume" {
                history.setPaused(command == "pause")
                break
            }
            if command == "enable" || command == "disable" {
                history.setEnabled(command == "enable")
                break
            }
            if command == "seed" {
                seed()
                return
            }
            if command.hasPrefix("filter:"), let filter = ClipboardFilter(rawValue: String(command.dropFirst("filter:".count))) {
                model.filter = filter
                break
            }
            if command.hasPrefix("select:"), let number = Int(command.dropFirst("select:".count)),
               model.rows.indices.contains(number - 1) {
                model.select(model.rows[number - 1].id)
                break
            }
            // Pilot step 2 checks: open each themed window with sample content, switch theme,
            // and snapshot any DocShot window by a word in its title or class.
            switch command {
            case "open-settings":
                AppDelegate.debugInstance?.openSettingsWindow()
                return writeState(command)
            case "open-onboarding":
                OnboardingWindowController.shared.showOnboarding()
                return writeState(command)
            case "open-permission":
                PermissionWindowController.shared.showPermissionAlert()
                return writeState(command)
            case "open-thumbnail":
                if let image = sampleCGImage() {
                    PreviewThumbnailController.shared.present(image: image, on: NSScreen.main, focusReturnApp: nil)
                }
                return writeState(command)
            case "open-editor":
                if let image = sampleCGImage() {
                    EditorWindowController.shared.presentEditor(with: image)
                }
                return writeState(command)
            case "windows":
                return writeState("windows: " + NSApp.windows.filter(\.isVisible)
                    .map { "\(type(of: $0))|\($0.title)" }.joined(separator: ", "))
            default:
                break
            }
            if command.hasPrefix("theme:"), (ProcessInfo.processInfo.environment["DOCSHOT_DEBUG_STORE"] ?? "").isEmpty {
                return writeState("refused: theme needs DOCSHOT_DEBUG_STORE")
            }
            if command.hasPrefix("theme:"), let theme = ColorTheme(rawValue: String(command.dropFirst("theme:".count))) {
                ThemeController.shared.select(theme)
                return writeState(command)
            }
            if command.hasPrefix("snapwin:") {
                // snapwin:<word>:<path prefix>
                let rest = command.dropFirst("snapwin:".count)
                guard let colon = rest.firstIndex(of: ":") else { return writeState("snapwin: bad command") }
                let word = String(rest[..<colon]).lowercased()
                let prefix = URL(fileURLWithPath: String(rest[rest.index(after: colon)...]))
                guard let target = NSApp.windows.first(where: {
                    $0.isVisible && ("\(type(of: $0))|\($0.title)").lowercased().contains(word)
                }) else { return writeState("snapwin: no visible window matches \(word)") }
                snapshot(target, to: prefix)
                return
            }
            if command.hasPrefix("menubar:") {
                // The menu bar item, drawn by DocShot itself, in dark and light.
                let prefix = URL(fileURLWithPath: String(command.dropFirst("menubar:".count)))
                let bars = NSApp.windows.filter { String(describing: type(of: $0)).contains("StatusBar") }
                for (index, bar) in bars.enumerated() {
                    guard let view = bar.contentView else { continue }
                    for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                        view.appearance = NSAppearance(named: appearance)
                        view.layoutSubtreeIfNeeded()
                        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                        view.cacheDisplay(in: view.bounds, to: rep)
                        let url = prefix.deletingLastPathComponent()
                            .appendingPathComponent(prefix.lastPathComponent + "-\(index)-\(name).png")
                        try? rep.representation(using: .png, properties: [:])?.write(to: url)
                    }
                    view.appearance = nil
                }
                return writeState("menubar: \(bars.count) item(s)")
            }
            if command.hasPrefix("snapshot:") {
                snapshot(to: URL(fileURLWithPath: String(command.dropFirst("snapshot:".count))))
                return
            }
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

    /// Sample items of every kind, added straight to the store (no clipboard), so the look can
    /// be checked. Text samples start with "DocShot sample" so they are easy to clear.
    static func seed() {
        let history = ClipboardHistoryController.shared
        let now = Date()
        let lastWeek = now.addingTimeInterval(-6 * 86_400)
        history.debugAdd(.fileURLs([URL(fileURLWithPath: NSHomeDirectory() + "/Documents/docshot/docs/DOCSHOT_REDEFINITION_PLAN.md")]),
                         sourceApp: "com.apple.finder", at: lastWeek)
        history.debugAdd(.text("DocShot sample: the earlier note from last week"), sourceApp: "com.apple.Notes", at: lastWeek.addingTimeInterval(60))
        history.debugAdd(.image(data: sampleImage(), typeIdentifier: "public.png"), sourceApp: "com.apple.Preview", at: now.addingTimeInterval(-840))
        history.debugAdd(.text("DocShot sample: Thanks, I will send the C2 notes over tonight."), sourceApp: "com.apple.MobileSMS", at: now.addingTimeInterval(-600))
        history.debugAdd(.text("https://developer.apple.com/design/human-interface-guidelines"), sourceApp: "com.apple.Safari", at: now.addingTimeInterval(-540))
        history.debugAdd(.colour(ClipColour(red: 0.914, green: 0.447, blue: 0.298)), sourceApp: "com.figma.Desktop", at: now.addingTimeInterval(-120))
        history.debugAdd(.text("DocShot sample: ssh noel@devbox.local -p 2222"), sourceApp: "com.apple.Terminal", at: now.addingTimeInterval(-60))
        Task {
            await history.waitUntilIdle()
            if let ssh = history.items.first(where: { $0.preview.hasPrefix("DocShot sample: ssh") }), !ssh.pinned {
                history.togglePin(ssh)
                await history.waitUntilIdle()
            }
            writeState("seed")
        }
    }

    /// A built-in macOS desktop picture (never the user's own photos), downscaled, so preview
    /// sharpness can be judged; a gradient if it is missing.
    private static func sampleCGImage() -> CGImage? {
        let data = sampleImage() as CFData
        guard let source = CGImageSourceCreateWithData(data, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func sampleImage() -> Data {
        let photo = URL(fileURLWithPath: "/System/Library/Desktop Pictures/Sonoma.heic")
        if let source = CGImageSourceCreateWithURL(photo as CFURL, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceThumbnailMaxPixelSize: 1600,
           ] as CFDictionary),
           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            return png
        }
        let side = 480
        let context = CGContext(data: nil, width: side, height: side * 3 / 4, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colours = [CGColor(srgbRed: 0.31, green: 0.82, blue: 0.71, alpha: 1), CGColor(srgbRed: 0.45, green: 0.71, blue: 1, alpha: 1)]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side * 3 / 4), options: [])
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        return bitmap.representation(using: .png, properties: [:]) ?? Data()
    }

    /// Renders the window's content in dark and then light appearance to `<prefix>-dark.png`
    /// and `<prefix>-light.png`, then restores the appearance.
    static func snapshot(to prefix: URL) {
        guard let window = ClipboardWindowController.shared.debugWindow else {
            return writeState("snapshot: no window")
        }
        snapshot(window, to: prefix)
    }

    static func snapshot(_ window: NSWindow, to prefix: URL) {
        guard let view = window.contentView else { return writeState("snapshot: no content") }
        Task {
            for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                window.appearance = NSAppearance(named: appearance)
                try? await Task.sleep(for: .milliseconds(500))
                view.layoutSubtreeIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = prefix.deletingLastPathComponent()
                    .appendingPathComponent(prefix.lastPathComponent + "-\(name).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
            window.appearance = nil
            writeState("snapshot")
        }
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
