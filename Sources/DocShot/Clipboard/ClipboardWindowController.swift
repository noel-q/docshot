import AppKit
import ClipboardKit
import SwiftUI

/// The DocShot clipboard panel (plan section 3; compact panels, 24 November 2026), opened from
/// the menu bar or its shortcut: a borderless rounded panel at the normal window level. Return or a click pastes into the app the user was
/// in; Escape closes and focus goes back there (C3 plan, decisions 1, 4 and 9).
@MainActor
final class ClipboardWindowController: NSObject, NSWindowDelegate {
    static let shared = ClipboardWindowController()

    let model = ClipboardWindowModel(controller: .shared)
    private var window: NSWindow?
    /// The app to paste into and to return to: the last other app made active.
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    private var konami = KonamiTracker()
    private var activationObserver: NSObjectProtocol?
    /// A choice is being copied and pasted; a second Return or click waits for it.
    private var isChoosing = false
#if DEBUG
    /// What the last choice did, for the debug hooks (debug builds only).
    private(set) var lastPasteReport = "none"
    var debugPreviousApp: String? { previousApp?.bundleIdentifier }
    func debugSetPreviousApp(_ app: NSRunningApplication) { previousApp = app }
    var debugWindow: NSWindow? { window }
#endif

    var isShowing: Bool { window?.isVisible == true }

    /// The shortcut opens the window, or closes it when it is already in front.
    func toggle() {
        if let window, window.isVisible, window.isKeyWindow, NSApp.isActive {
            close()
        } else {
            show()
        }
    }

    func show() {
        // On open, the front app is the one the user was in, even a menu bar app such as a
        // launcher; later activations count only for ordinary apps (see watchActivations).
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        watchActivations()

        let window = self.window ?? makeWindow()
        let wasShowing = window.isVisible
        self.window = window
        let history = ClipboardHistoryController.shared
        history.refreshAccessState()
        history.refreshPasteAccess()
        history.clearNotice()
        model.reset()
        if !wasShowing { place(window) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        window?.close() // windowWillClose hands focus back
    }

    // MARK: - Choosing an item

    /// Return or a click: copy, close, and paste into the previous app when allowed.
    func choose(_ item: ClipItem) {
        guard !isChoosing else { return }
        isChoosing = true
        let history = ClipboardHistoryController.shared
        let target = previousApp.flatMap { $0.isTerminated ? nil : $0 }
        let outcome = history.pasteOutcome(hasPreviousApp: target != nil)
        Task {
            guard await history.copyBack(item) else { // stays open; the problem shows
                self.isChoosing = false
                return
            }
            close()
            self.isChoosing = false
#if DEBUG
            self.lastPasteReport = "\(outcome) target=\(target?.bundleIdentifier ?? "none")"
#endif
            switch outcome {
            case .pasteIntoPreviousApp:
                let started = ContinuousClock.now
                guard let target, await PasteKeystroke.waitUntilFrontmost(target) else {
#if DEBUG
                    self.lastPasteReport += " never frontmost"
#endif
                    // The app did not come back in time: the item is on the clipboard, so a beep
                    // says to press Cmd+V rather than pasting into whatever is in front.
                    NSSound.beep()
                    return
                }
                let frontAfter = ContinuousClock.now - started
                // Apps built on web views (Electron, such as Claude) put focus back in their text
                // field some time after they come to the front; a keystroke before that is lost.
                let focused = await PasteKeystroke.waitForFocusedElement(in: target)
                try? await Task.sleep(for: .milliseconds(50))
                // Pasting into whatever replaced the target meanwhile would be worse than not pasting.
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
#if DEBUG
                    self.lastPasteReport += " left the front before the keystroke"
#endif
                    NSSound.beep()
                    return
                }
                let posted = PasteKeystroke.postCommandV()
#if DEBUG
                self.lastPasteReport += " frontmost after \(frontAfter) focused=\(focused) after \(ContinuousClock.now - started) posted=\(posted) key=\(PasteKeystroke.keyCodeForV())"
#endif
            case .copyOnly(let askForAccess):
                if askForAccess {
                    history.markAccessRequested()
                    AccessibilityAccess.request()
                }
            }
        }
    }

    /// Cmd+C: copy and close; the user pastes.
    func copyOnly(_ item: ClipItem) {
        Task {
            if await ClipboardHistoryController.shared.copyBack(item) {
                close()
            }
        }
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: ClipboardPanelLayout.listWidth, height: ClipboardPanelLayout.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // The thumbnail's style (compact panels, decision 1): no title bar, the SwiftUI content
        // draws the rounded shape, and the system draws the shadow around it.
        panel.title = "DocShot Clipboard"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        // Behaves like the window it replaces: stays open when another app is used, so the
        // previous-app tracking (C3 plan, decision 9) still works.
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        let host = NSHostingView(rootView: ClipboardHistoryView(
            model: model,
            controller: ClipboardHistoryController.shared,
            onChoose: { [weak self] item in self?.choose(item) },
            onClose: { [weak self] in self?.close() },
            onTogglePreview: { [weak self] in self?.togglePreview() },
            onCaptureAction: { [weak self] action, capture in self?.perform(action, on: capture) }
        ))
        // The panel's size is DocShot's to animate; the content must not force it (it would
        // snap the panel wide the moment the preview pane is laid out).
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    // MARK: - Place and size (compact panels, decisions 2 and 3)

    /// The clipboard controller's preferences (scratch ones in a debug run on a scratch store).
    private var panelSettings: ClipboardSettings { ClipboardHistoryController.shared.preferences }
    /// Counts DocShot's own moves of the panel; a drag is remembered only when none is running.
    /// A counter, not a flag, so an older animation finishing cannot clear a newer one's mark.
    private var animationsRunning = 0
    /// Where the panel's left edge was before the preview pushed it left, to go back on folding.
    private var minXBeforePreview: CGFloat?

    /// The screen the pointer is on: the one in use. NSMouseInRect counts the screen's edges.
    private static var screenInUse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func place(_ window: NSWindow) {
        let visible = (Self.screenInUse ?? window.screen)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = ClipboardPanelLayout.frame(
            visible: visible, savedOrigin: panelSettings.panelOrigin, showingPreview: model.showPreview
        )
        minXBeforePreview = nil
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Rises 8 points and fades in over dur-base, moving the window itself so the shadow
        // follows (Reduce Motion: fade only).
        window.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: -Quiet.Space.s2), display: false)
        window.alphaValue = 0
        animate(window, reduceMotion: false) {
            window.animator().alphaValue = 1
            if !reduceMotion { window.animator().setFrame(frame, display: true) }
        }
    }

    /// Runs one of DocShot's own panel animations over dur-base with Quiet's ease-out.
    private func animate(_ window: NSWindow, reduceMotion: Bool, changes: @escaping () -> Void,
                         completion: (@MainActor () -> Void)? = nil) {
        animationsRunning += 1
        let done: @MainActor () -> Void = { [weak self] in
            self?.animationsRunning -= 1
            completion?()
        }
        if reduceMotion {
            changes()
            done()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = QuietTokens.durBase
            context.timingFunction = Quiet.Motion.easeOutCurve
            changes()
        }, completionHandler: {
            MainActor.assumeIsolated { done() }
        })
    }

    /// Cmd+Y or the footer hint: slide the preview pane out to the right, or fold it away.
    /// The content changes first and the panel's edge animates on the next turn of the run
    /// loop, never the other way round: a layout change during a window animation cuts it
    /// short (traced frame by frame, 24 November 2026). Widening reveals the new pane; narrowing
    /// lets the pane fade out quickly and the panel close over the space it left. Ignored while
    /// the panel is still rising in or already resizing.
    func togglePreview() {
        guard let window, window.isVisible, animationsRunning == 0 else { return }
        let showing = !model.showPreview
        let visible = window.screen?.visibleFrame ?? (Self.screenInUse?.visibleFrame ?? window.frame)
        var target = ClipboardPanelLayout.resized(
            window.frame, toWidth: ClipboardPanelLayout.width(showingPreview: showing), within: visible
        )
        if showing {
            // Remember the left edge in case widening near the right of the screen moves it.
            minXBeforePreview = window.frame.minX
        } else if let minX = minXBeforePreview {
            // Folding goes back to where the panel was before the preview pushed it left.
            target.origin.x = min(max(minX, visible.minX), visible.maxX - target.width)
            minXBeforePreview = nil
        }
        model.showPreview = showing
        animationsRunning += 1 // held across the hop to the next turn of the run loop
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.animationsRunning -= 1
                self.animate(window, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
                    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                        window.setFrame(target, display: true)
                    } else {
                        window.animator().setFrame(target, display: true)
                    }
                }
            }
        }
    }

    /// Saves where the user left the panel. Only drags call this, never DocShot's own moves.
    private func rememberPlace(_ origin: CGPoint) {
        panelSettings.panelOrigin = origin
    }

    func windowDidMove(_ notification: Notification) {
        guard animationsRunning == 0, let window else { return }
        rememberPlace(window.frame.origin)
        // A drag sets a new home for the left edge.
        minXBeforePreview = nil
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelSearch()
        removeKeyMonitor()
        stopWatchingActivations()
        ClipboardHistoryController.shared.releaseSearchIndex()
        returnFocus()
    }

    private func returnFocus() {
        guard let app = previousApp, !app.isTerminated else { return }
        previousApp = nil
        app.activate()
    }

    /// An ordinary app other than DocShot: not a helper or system agent that takes focus briefly.
    private static func canReceivePaste(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier != ProcessInfo.processInfo.processIdentifier && app.activationPolicy == .regular
    }

    // MARK: - Previous app (C3 plan, decision 9)

    /// While the window is open, the last other app made active becomes the one to paste into.
    private func watchActivations() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app, Self.canReceivePaste(app) else { return }
                self.previousApp = app
            }
        }
    }

    private func stopWatchingActivations() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    // MARK: - Keys (C3 plan, decision 4)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            return self.handle(event, in: window) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// True when the key was used here; false lets the search field have it.
    private func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        // The Konami code (easter egg): the keys still do their usual work, except the final A,
        // and the B it follows is taken back out of the search.
        let hasModifiers = !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        let konamiKey = KonamiKey.from(
            keyCode: event.keyCode, characters: event.charactersIgnoringModifiers?.lowercased(),
            hasModifiers: hasModifiers
        )
        if konami.record(event.isARepeat ? nil : konamiKey, at: event.timestamp) {
            if model.query.hasSuffix("b") { model.query.removeLast() }
            // The field being edited does not redraw from the model at once; take the B out
            // of it too, so it is gone before the snapshot is taken.
            if let editor = window.firstResponder as? NSTextView, editor.string.hasSuffix("b") {
                editor.string.removeLast()
            }
            // DocShot takes a picture of itself: a flash, the snapshot flies to the menu bar
            // icon, the icon winks as it lands, and a small card says what happened.
            // On the next pass, so the picture is taken after the B has left the search.
            DispatchQueue.main.async { [weak self] in
                SnapshotFlight.shared.play(from: window) {
                    MenuBarWink.shared.play()
                    withAnimation(nil) { self?.model.konamiFound = true }
                }
            }
            return true
        }
        if model.section == .captures, ClipboardHistoryController.shared.isEnabled {
            return handleCaptures(event)
        }
        let fieldEditor = window.firstResponder as? NSTextView
        let action = ClipboardKeys.action(
            keyCode: event.keyCode, modifiers: event.modifierFlags, characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            hasMarkedText: fieldEditor?.hasMarkedText() == true,
            hasTextSelection: (fieldEditor?.selectedRange().length ?? 0) > 0,
            queryIsEmpty: model.query.isEmpty
        )
        let history = ClipboardHistoryController.shared
        // History off: only Escape is ours; Return reaches the Turn On button.
        if !history.isEnabled, action != .close, action != .clearSearch { return false }
        switch action {
        case .passThrough:
            return false
        case .close:
            close()
        case .clearSearch:
            model.query = ""
        case .up:
            model.moveSelection(by: -1)
        case .down:
            model.moveSelection(by: 1)
        case .togglePreview:
            togglePreview()
        case .switchSection:
            // With Full Keyboard Access on, Tab moves focus between controls as usual; the tabs
            // are still a click away.
            if NSApp.isFullKeyboardAccessEnabled { return false }
            model.switchSection()
        case .float:
            Task {
                guard let item = await self.model.settledSelection(), item.kind == .image,
                      let url = await history.imageFileURL(for: item),
                      let image = await Task.detached(priority: .userInitiated, operation: {
                          (try? Data(contentsOf: url)).flatMap(FloatController.image(fromPNG:))
                      }).value else {
                    NSSound.beep()
                    return
                }
                FloatController.shared.float(image)
            }
        case .copyText:
            Task {
                guard let item = await self.model.settledSelection(), item.kind == .image,
                      let text = await history.recognisedText(for: item), !text.isEmpty else {
                    NSSound.beep()
                    return
                }
                history.copyRecognisedText(text)
            }
        case .pick(let number):
            Task {
                guard let item = await self.model.settledRow(number), self.isShowing else { return }
                self.model.select(item.id)
                self.choose(item)
            }
        case .choose, .copy, .togglePin, .delete:
            // Act on the list the search is about to show, not the one before it.
            Task {
                // Closed meanwhile (Escape straight after Return): do nothing.
                guard let item = await self.model.settledSelection(), self.isShowing else { return }
                switch action {
                case .choose: self.choose(item)
                case .copy: self.copyOnly(item)
                case .togglePin: history.togglePin(item)
                default: history.delete(item)
                }
            }
        }
        return true
    }
}

// MARK: - Captures (C4)

extension ClipboardWindowController {
    /// Keys in Captures (C4 plan, decision 4).
    func handleCaptures(_ event: NSEvent) -> Bool {
        let action = CaptureKeys.action(
            keyCode: event.keyCode, modifiers: event.modifierFlags, characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers
        )
        switch action {
        case .passThrough:
            return false
        case .close:
            close()
        case .switchSection:
            if NSApp.isFullKeyboardAccessEnabled { return false }
            model.switchSection()
        case .left, .right, .up, .down:
            model.moveCaptureSelection(action)
        case .choose, .copy, .edit, .save, .delete, .float:
            guard let capture = model.selectedCapture else {
                NSSound.beep()
                return true
            }
            perform(action, on: capture)
        }
        return true
    }

    /// One action on a capture; clicks in the section come here too.
    func perform(_ action: CaptureKeyAction, on capture: CaptureItem) {
        let history = ClipboardHistoryController.shared
        model.selectedCaptureID = capture.id
        if capture.kind == .recording {
            switch action {
            case .choose: revealRecording(capture)
            case .delete: history.deleteCapture(capture)
            default: NSSound.beep()
            }
            return
        }
        switch action {
        case .choose, .copy:
            Task {
                guard let png = await history.renderedCapture(capture), OutputService.shared.copyToClipboard(pngData: png) else {
                    NSSound.beep()
                    return
                }
                if action == .choose { self.close() }
            }
        case .edit:
            Task {
                guard let contents = await history.captureContents(capture),
                      CaptureCoordinator.shared.beginReopenedEditing() else {
                    NSSound.beep()
                    return
                }
                self.close()
                EditorWindowController.shared.presentEditor(with: contents.image, captureID: capture.id, state: contents.state)
            }
        case .save:
            Task {
                guard let png = await history.renderedCapture(capture) else {
                    NSSound.beep()
                    return
                }
                self.close()
                _ = await OutputService.shared.saveWithPanel(pngData: png, parentWindow: nil)
            }
        case .delete:
            history.deleteCapture(capture)
        case .float:
            Task {
                guard let png = await history.renderedCapture(capture), let image = FloatController.image(fromPNG: png) else {
                    NSSound.beep()
                    return
                }
                FloatController.shared.float(image)
            }
        default:
            break
        }
    }

    func revealRecording(_ capture: CaptureItem) {
        guard let path = capture.filePath, FileManager.default.fileExists(atPath: path) else {
            NSSound.beep()
            return
        }
        close()
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

/// A borderless panel that still takes the keyboard (the search field) and stays at the normal
/// window level, so it behaves like a window, not an overlay.
final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The Konami code's snapshot (easter egg, 27 November 2026): a soft camera flash over the
/// clipboard window, then a picture of the window springs up along a curve into DocShot's
/// menu bar icon, about 0.7 s in all. With Reduce Motion: a dimmer flash and no flight.
/// It draws in its own click-through window, so the clipboard window keeps working.
@MainActor
final class SnapshotFlight {
    static let shared = SnapshotFlight()

    private var overlay: NSPanel?
    /// True while the snapshot plays (read by the debug hook).
    var isPlaying: Bool { overlay != nil }
    /// Where the last snapshot was sent (read by the debug hook).
    private(set) var lastLanding = ""

    func play(from window: NSWindow, landed: @escaping @MainActor () -> Void) {
        guard overlay == nil, let content = window.contentView, let screen = window.screen ?? NSScreen.main else {
            landed()
            return
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let slowdown = EggMotion.slowdown
        let screenFrame = screen.frame
        let contentRect = window.convertToScreen(content.convert(content.bounds, to: nil))
            .offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        let radius = Quiet.Radius.lg

        let panel = NSPanel(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: max(window.level.rawValue, NSWindow.Level.statusBar.rawValue) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let host = NSView(frame: NSRect(origin: .zero, size: screenFrame.size))
        host.wantsLayer = true
        panel.contentView = host
        guard let root = host.layer else { landed(); return }
        root.speed = Float(1 / slowdown)
        panel.setFrame(screenFrame, display: false)
        panel.orderFrontRegardless()
        overlay = panel

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.overlay?.orderOut(nil)
            self?.overlay = nil
        }

        // The flash: up quickly, down gently, over the window's own rounded shape.
        let flash = CALayer()
        flash.frame = contentRect
        flash.cornerRadius = radius
        flash.cornerCurve = .continuous
        flash.backgroundColor = NSColor.white.cgColor
        flash.opacity = 0
        root.addSublayer(flash)
        let flashAnimation = CAKeyframeAnimation(keyPath: "opacity")
        flashAnimation.values = reduceMotion ? [0, 0.3, 0] : [0, 0.75, 0]
        flashAnimation.keyTimes = [0, 0.25, 1]
        flashAnimation.duration = 0.4
        flash.add(flashAnimation, forKey: "flash")

        let landing = Self.iconRect(on: screen).offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        lastLanding = "icon=\(NSApp.windows.first { $0.className.contains("StatusBarWindow") }?.frame ?? .zero) "
            + "screen=\(screenFrame) landing=\(landing) reduceMotion=\(reduceMotion)"
        if reduceMotion {
            CATransaction.commit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 * slowdown) { landed() }
            return
        }

        // The snapshot, lifted off the window as the flash peaks.
        let snapshot = CALayer()
        snapshot.frame = contentRect
        snapshot.contents = Self.picture(of: content)
        snapshot.contentsGravity = .resizeAspectFill
        snapshot.cornerRadius = radius
        snapshot.cornerCurve = .continuous
        snapshot.masksToBounds = true
        snapshot.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        snapshot.borderWidth = 3
        snapshot.opacity = 0
        root.addSublayer(snapshot)

        // In the overlay's own clock, which the debug slow-down stretches.
        let begin = root.convertTime(CACurrentMediaTime(), from: nil) + 0.08
        let flightTime = 0.62
        let start = CGPoint(x: contentRect.midX, y: contentRect.midY)
        let end = CGPoint(x: landing.midX, y: landing.midY)
        // A curve that rises from the window and arrives at the icon from just below it.
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2 + (end.x - start.x) * 0.35,
                                                    y: start.y + (end.y - start.y) * 0.2))
        let curve = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)

        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.timingFunction = curve
        let endScale = max(landing.height / contentRect.height, 0.02)
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1, 0.9, endScale]
        scale.keyTimes = [0, 0.18, 1]
        scale.timingFunctions = [CAMediaTimingFunction(name: .easeOut), curve]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.8, 1]
        let group = CAAnimationGroup()
        group.animations = [move, scale, fade]
        group.beginTime = begin
        group.duration = flightTime
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        snapshot.add(group, forKey: "flight")

        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + (0.08 + flightTime * 0.92) * slowdown) { landed() }
    }

    /// A picture of the window's content, as drawn now.
    private static func picture(of view: NSView) -> CGImage? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    /// DocShot's menu bar icon on this screen, from its status item window. When macOS hides
    /// the icon (a crowded menu bar puts it off screen), the snapshot still flies up into the
    /// menu bar, above where the icon would be, or near the right-hand end.
    private static func iconRect(on screen: NSScreen) -> NSRect {
        let frame = screen.frame
        let icon = NSApp.windows.first { $0.className.contains("StatusBarWindow") }?.frame ?? .zero
        if icon.intersects(frame) { return icon }
        let barHeight = max(24, frame.maxY - screen.visibleFrame.maxY)
        let x = (frame.minX + 40...frame.maxX - 40).contains(icon.midX) ? icon.midX : frame.maxX - 160
        return NSRect(x: x - 11, y: frame.maxY - barHeight, width: 22, height: barHeight)
    }
}
