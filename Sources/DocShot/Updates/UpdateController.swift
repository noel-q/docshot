import AppKit
import SwiftUI

/// Update notices (decided 26 November 2026; plan section "Update notices"). Asks GitHub once a
/// day, shows the guide once per new build unless notices are off, and keeps the update in the
/// DocShot menu either way. Never downloads or installs anything by itself.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    static let shared = UpdateController()

    static let noticesKey = "DocShotUpdateNotices"
    static let lastCheckKey = "DocShotUpdateLastCheck"
    static let lastNotifiedBuildKey = "DocShotUpdateLastNotifiedBuild"
    /// The update last found, so a relaunch still shows it until the next check.
    static let availableKey = "DocShotUpdateAvailable"
    static let identifier = NSUserInterfaceItemIdentifier("DocShotUpdate")

    /// Who asked for a check: the daily timer says nothing unless there is an update; the menu
    /// answers with an alert; Settings shows the answer in its own row.
    enum CheckOrigin { case automatic, menu, settings }

    @Published private(set) var available: AvailableUpdate?
    @Published private(set) var noticesOn: Bool
    @Published private(set) var lastChecked: Date?
    @Published private(set) var checking = false
    @Published private(set) var lastError: String?

    let currentBuild: Int
    let currentVersion: String

    private var timer: Timer?
    private var panel: UpdatePanel?
    private var keyMonitor: Any?

    /// Scratch preferences in debug runs with a scratch store, like the guide's.
    private var preferences: UserDefaults { OnboardingWindowController.preferences }

    private override init() {
        let defaults = OnboardingWindowController.preferences
        noticesOn = (defaults.object(forKey: Self.noticesKey) as? Bool) ?? true
        lastChecked = defaults.object(forKey: Self.lastCheckKey) as? Date
        currentBuild = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        super.init()
        if let saved = defaults.data(forKey: Self.availableKey),
           let update = try? JSONDecoder().decode(AvailableUpdate.self, from: saved), update.build > currentBuild {
            available = update
        }
    }

    var currentDisplayVersion: String { "\(currentVersion) (build \(currentBuild))" }

    /// Called once at launch: the first check a minute in, then a look every hour.
    func start() {
#if DEBUG
        // Hook-driven debug runs never ask GitHub; the hooks feed releases instead.
        if ProcessInfo.processInfo.environment["DOCSHOT_DEBUG_HOOKS"] == "1" { return }
#endif
        Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 5 * 60
    }

    private func tick() {
        if UpdateRelease.isCheckDue(lastCheck: lastChecked, now: Date()) {
            check(.automatic)
        } else {
            notifyIfDue()
        }
    }

    func setNoticesOn(_ on: Bool) {
        noticesOn = on
        preferences.set(on, forKey: Self.noticesKey)
    }

    func check(_ origin: CheckOrigin) {
        guard !checking else { return }
        checking = true
        lastError = nil
        Task { @MainActor in
            defer { self.checking = false }
            do {
                let data = try await Self.fetchReleases()
                self.receive(data, origin: origin)
            } catch {
                self.lastError = "Could not reach GitHub. Check your connection and try again."
                if origin == .menu { self.showAlert("DocShot could not check for updates", self.lastError ?? "") }
            }
        }
    }

    /// What a check found. The debug hooks call this with a local file instead of GitHub.
    func receive(_ data: Data, origin: CheckOrigin, now: Date = Date()) {
        let found: AvailableUpdate?
        do {
            found = try UpdateRelease.newest(fromJSON: data, newerThan: currentBuild)
        } catch {
            // Not a releases list: keep what was known and try again at the next hourly look.
            lastError = "GitHub gave an answer DocShot could not read. Try again later."
            if origin == .menu { showAlert("DocShot could not check for updates", lastError ?? "") }
            return
        }
        lastChecked = now
        preferences.set(now, forKey: Self.lastCheckKey)
        available = found
        if let found, let encoded = try? JSONEncoder().encode(found) {
            preferences.set(encoded, forKey: Self.availableKey)
        } else {
            preferences.removeObject(forKey: Self.availableKey)
        }
        switch origin {
        case .automatic:
            notifyIfDue()
        case .menu:
            if available != nil { showGuide() } else {
                showAlert("DocShot is up to date", "You have \(currentDisplayVersion), the newest test build.")
            }
        case .settings:
            if available != nil { showGuide() }
        }
    }

    /// Shows the guide for a new build once, while notices are on, and never in the middle of
    /// a screenshot or a recording (the next hourly look tries again).
    private func notifyIfDue() {
        guard let available,
              UpdateRelease.shouldNotify(available, noticesOn: noticesOn, lastNotifiedBuild: preferences.integer(forKey: Self.lastNotifiedBuildKey)),
              !isCapturing else { return }
        // Shown without taking the keyboard from the app in front: Return and Escape there
        // stay theirs until the user clicks the guide.
        showGuide(takeFocus: false)
    }

    private var isCapturing: Bool {
        let policy = CaptureActivityPolicy.evaluate(
            captureState: CaptureCoordinator.shared.state, recordingState: RecordingCoordinator.shared.state
        )
        return !(policy.allowsScreenshotCapture && policy.allowsRecordingCapture)
    }

    nonisolated static func fetchReleases() async throws -> Data {
        var request = URLRequest(url: UpdateRelease.releasesURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DocShot-update-check", forHTTPHeaderField: "User-Agent")
        // No cookies, no cache, nothing kept between checks.
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - The guide

    var isShowingGuide: Bool { panel?.isVisible == true }

    /// Opens the guide. Any showing, asked for or not, counts as the notice for that build.
    func showGuide(takeFocus: Bool = true) {
        guard let update = available else { return }
        preferences.set(max(update.build, preferences.integer(forKey: Self.lastNotifiedBuildKey)), forKey: Self.lastNotifiedBuildKey)
        closeGuide()
        let view = UpdateGuideView(
            update: update,
            currentVersion: currentDisplayVersion,
            controller: self,
            onDownload: { [weak self] in self?.download() },
            onQuit: { NSApp.terminate(nil) },
            onClose: { [weak self] in self?.closeGuide() }
        )
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        let size = host.fittingSize
        let panel = UpdatePanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.identifier = Self.identifier
        panel.title = "Update DocShot"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = host

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.minY + (visible.height - size.height) * 2 / 3).rounded(),
            width: size.width, height: size.height
        )
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: -Quiet.Space.s2), display: false)
        panel.alphaValue = 0
        if takeFocus {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        self.panel = panel
        installKeyMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = QuietTokens.durBase
            context.timingFunction = Quiet.Motion.easeOutCurve
            panel.animator().alphaValue = 1
            if !reduceMotion { panel.animator().setFrame(frame, display: true) }
        }
    }

    func closeGuide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func download() {
        guard let url = available?.downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Return downloads (unless a button has focus); Escape and Cmd+W close.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel, !event.isARepeat else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let commandW = modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "w"
            if (event.keyCode == 53 && modifiers.isEmpty) || commandW {
                self.closeGuide()
                return nil
            }
            if (event.keyCode == 36 || event.keyCode == 76) && modifiers.isEmpty && !(panel.firstResponder is NSButton) {
                self.download()
                return nil
            }
            return event
        }
    }
}

final class UpdatePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The guide: what is new, four steps, and the choice to stop notices. Quiet: the guide's
/// compact panel, one accent (Download), Escape closes.
struct UpdateGuideView: View {
    @ObservedObject private var themeController = ThemeController.shared
    let update: AvailableUpdate
    let currentVersion: String
    @ObservedObject var controller: UpdateController
    let onDownload: () -> Void
    let onQuit: () -> Void
    let onClose: () -> Void

    static let width: CGFloat = 460

    var body: some View {
        VStack(alignment: .leading, spacing: Quiet.Space.s4) {
            HStack(alignment: .center, spacing: Quiet.Space.s4) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: Quiet.Space.s12, height: Quiet.Space.s12)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Quiet.Space.s1) {
                    Text("DocShot \(update.displayVersion) is ready")
                        .font(Quiet.Font.title3)
                        .foregroundStyle(Quiet.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("You have \(currentVersion). Your history and settings stay when you update.")
                        .font(Quiet.Font.nativeBody)
                        .foregroundStyle(Quiet.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !update.notes.isEmpty {
                SettingsGroup(title: "What's new") {
                    Text(update.notes)
                        .font(Quiet.Font.nativeBody)
                        .foregroundStyle(Quiet.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Quiet.Space.s4)
                }
            }

            SettingsGroup(title: "How to update") {
                SettingsRow(title: "1. Download it", detail: "Opens the download in your browser.") {
                    Button(action: onDownload) {
                        AccentButtonLabel("Download  ↵")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Quiet.accent)
                    .help("Download (Return)")
                    .accessibilityLabel("Download")
                }
                SettingsDivider()
                SettingsRow(title: "2. Quit DocShot", detail: "macOS cannot replace an app that is open.") {
                    Button("Quit DocShot", action: onQuit)
                }
                SettingsDivider()
                SettingsRow(title: "3. Replace it", detail: "Open the downloaded file, drag DocShot to Applications and choose Replace.") {
                    EmptyView()
                }
                SettingsDivider()
                SettingsRow(title: "4. Open DocShot", detail: "If macOS stops it, choose Open Anyway in System Settings, Privacy & Security.") {
                    EmptyView()
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Button(controller.noticesOn ? "Don't tell me about updates" : "Tell me about updates") {
                    controller.setNoticesOn(!controller.noticesOn)
                }
                .buttonStyle(.plain)
                .font(Quiet.Font.caption)
                .foregroundStyle(Quiet.inkMuted)
                .help(controller.noticesOn ? "Updates will still show in the DocShot menu." : "Show this when a new build is out.")
                Spacer(minLength: Quiet.Space.s4)
                Button(action: onClose) {
                    HStack(spacing: Quiet.Space.s1) {
                        KeyHint(keys: "esc")
                        Text("Later").font(Quiet.Font.caption).foregroundStyle(Quiet.inkMuted)
                    }
                }
                .buttonStyle(.plain)
                .help("Later (esc)")
                .accessibilityLabel("Later")
            }
            // Always one line high, so the panel never changes size.
            Text(controller.noticesOn ? "DocShot checks once a day." : "Notices are off. Updates still show in the DocShot menu.")
                .font(Quiet.Font.caption)
                .foregroundStyle(Quiet.inkFaint)
                .lineLimit(1, reservesSpace: true)
        }
        .padding(Quiet.Space.s6)
        .frame(width: Self.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Quiet.canvas)
        .clipShape(RoundedRectangle(cornerRadius: Quiet.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Quiet.Radius.lg, style: .continuous).strokeBorder(Quiet.line, lineWidth: 1))
        .ignoresSafeArea()
    }
}
