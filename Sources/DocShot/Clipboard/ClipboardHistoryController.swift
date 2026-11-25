import AppKit
import ClipboardKit

/// Runs clipboard history in the app (plan sections 4.3 and C2): watches the general pasteboard
/// while history is on and not paused, saves copies through `ClipboardStore`, and copies items
/// back. With history off it does nothing at all: no timer, no store, no reads.
@MainActor
final class ClipboardHistoryController: ObservableObject {
    static let shared: ClipboardHistoryController = {
#if DEBUG
        // Debug runs for checking the look: `open --env DOCSHOT_DEBUG_STORE=<folder>` keeps
        // history in that folder with scratch preferences, away from the real ones.
        if let folder = ProcessInfo.processInfo.environment["DOCSHOT_DEBUG_STORE"], !folder.isEmpty,
           let defaults = UserDefaults(suiteName: "DocShotDebugStore") {
            return ClipboardHistoryController(
                settings: ClipboardSettings(defaults: defaults),
                storeDirectory: URL(fileURLWithPath: folder, isDirectory: true)
            )
        }
#endif
        return ClipboardHistoryController()
    }()

    @Published private(set) var items: [ClipItem] = []
    /// Screenshots and saved recordings, newest first (C4).
    @Published private(set) var captures: [CaptureItem] = []
    @Published private(set) var isEnabled = false
    @Published private(set) var isPaused = false
    @Published private(set) var clearKeep: ClearKeep = .defaultValue
    /// macOS asks before, or refuses, clipboard reads for DocShot (plan 4.3, C0 finding).
    @Published private(set) var accessBlocked = false
    /// The last problem worth showing in Settings, such as a store that would not open.
    @Published private(set) var problem: String?
    /// A short message for the window, such as a refused pin. Cleared by the next action.
    @Published private(set) var notice: String?
    /// The limit choices in Settings (C3 plan, decision 6); nil items means no limit.
    @Published private(set) var maxItems: Int? = RetentionLimits.defaultMaxItems
    @Published private(set) var maxAgeDays = 30
    @Published private(set) var maxMegabytes = 500
    /// Apps whose copies are never recorded (C3 plan, decision 7).
    @Published private(set) var excludedApps: [String] = []
    /// Paste into the previous app when allowed; and whether Accessibility allows it.
    @Published private(set) var pasteDirectly = true
    @Published private(set) var pasteAllowed = false

    /// Polling interval (plan 4.3: about twice a second).
    static let pollInterval: TimeInterval = 0.5
    static let retentionInterval: TimeInterval = 60 * 60

    private let settings: ClipboardSettings
    private let pasteboard: NSPasteboard
    /// Nil means the real store folder; tests pass a temporary one.
    private let storeDirectory: URL?
    /// Nil means the real front app; tests pass a fixed one.
    private let frontmostApp: (() -> String?)?
    /// Whether Accessibility is granted; tests pass a fixed answer.
    private let accessibilityAllowed: () -> Bool
    private var rules = RecordingRules()
    private var store: ClipboardStore?
    private var pollTimer: Timer?
    private var retentionTimer: Timer?
    private var lastChangeCount = 0
    /// Change counts produced by copying from the history window.
    private var ownWriteChangeCounts: Set<Int> = []
    /// Store work runs one change at a time, in the order the copies happened.
    private var pendingWork: Task<Void, Never>?

    init(
        settings: ClipboardSettings = ClipboardSettings(),
        pasteboard: NSPasteboard = .general,
        storeDirectory: URL? = nil,
        frontmostApp: (() -> String?)? = nil,
        accessibilityAllowed: @escaping () -> Bool = { AccessibilityAccess.isAllowed }
    ) {
        self.settings = settings
        self.pasteboard = pasteboard
        self.storeDirectory = storeDirectory
        self.frontmostApp = frontmostApp
        self.accessibilityAllowed = accessibilityAllowed
        loadSettings()
    }

    private func loadSettings() {
        clearKeep = settings.clearKeep
        isPaused = settings.paused
        maxItems = settings.maxItems
        maxAgeDays = settings.maxAgeDays
        maxMegabytes = settings.maxMegabytes
        excludedApps = settings.excludedApps
        rules.excludedBundleIDs = Set(excludedApps)
        pasteDirectly = settings.pasteDirectly
    }

    /// The clipboard preferences this controller uses (scratch ones in tests and debug runs),
    /// for the window's own choices such as the preview pane and the panel's place.
    var preferences: ClipboardSettings { settings }

    /// Called once at launch.
    func start() {
        loadSettings()
        refreshPasteAccess()
        if settings.historyEnabled {
            turnOn()
        }
    }

    // MARK: - Settings

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        settings.historyEnabled = enabled
        if enabled {
            turnOn()
        } else {
            turnOff()
        }
    }

    func setPaused(_ paused: Bool) {
        settings.paused = paused
        isPaused = paused
        guard isEnabled else { return }
        if paused {
            stopWatching()
        } else {
            startWatching()
        }
    }

    func setClearKeep(_ keep: ClearKeep) {
        settings.clearKeep = keep
        clearKeep = keep
    }

    // MARK: - Limits (C3 plan, decision 6)

    var limits: RetentionLimits { settings.limits }

    /// The limits a choice would give, without saving it.
    func limits(maxItems: Int?, maxAgeDays: Int, maxMegabytes: Int) -> RetentionLimits {
        RetentionLimits(
            maxItems: maxItems ?? RetentionLimits.noItemLimit,
            maxAge: TimeInterval(maxAgeDays) * 86_400,
            maxBytes: maxMegabytes * 1024 * 1024
        )
    }

    /// How many items new limits would remove now, so Settings can ask first.
    func removalCount(for newLimits: RetentionLimits) -> Int {
        RetentionPolicy.itemsToRemove(from: items, limits: newLimits, now: Date()).count
    }

    /// Saves the limits and applies them at once. If the store cannot apply them, the previous
    /// limits are put back, so Settings never shows limits the store is not using.
    func setLimits(maxItems: Int?, maxAgeDays: Int, maxMegabytes: Int) {
        let previous = (settings.maxItems, settings.maxAgeDays, settings.maxMegabytes)
        settings.maxItems = maxItems
        settings.maxAgeDays = maxAgeDays
        settings.maxMegabytes = maxMegabytes
        self.maxItems = settings.maxItems
        self.maxAgeDays = settings.maxAgeDays
        self.maxMegabytes = settings.maxMegabytes
        let newLimits = settings.limits
        enqueue { store in
            do {
                try await store.setLimits(newLimits)
            } catch {
                self.settings.maxItems = previous.0
                self.settings.maxAgeDays = previous.1
                self.settings.maxMegabytes = previous.2
                self.maxItems = previous.0
                self.maxAgeDays = previous.1
                self.maxMegabytes = previous.2
                throw error
            }
        }
    }

    // MARK: - Excluded apps (C3 plan, decision 7)

    func addExcludedApp(_ bundleID: String) {
        guard !excludedApps.contains(bundleID) else { return }
        saveExcludedApps(excludedApps + [bundleID])
    }

    func removeExcludedApp(_ bundleID: String) {
        saveExcludedApps(excludedApps.filter { $0 != bundleID })
    }

    func restoreDefaultExcludedApps() {
        settings.restoreDefaultExcludedApps()
        excludedApps = settings.excludedApps
        rules.excludedBundleIDs = Set(excludedApps)
    }

    private func saveExcludedApps(_ apps: [String]) {
        settings.excludedApps = apps
        excludedApps = apps
        rules.excludedBundleIDs = Set(apps)
    }

    // MARK: - Paste (C3 plan, decisions 1 and 2)

    func setPasteDirectly(_ on: Bool) {
        settings.pasteDirectly = on
        pasteDirectly = on
    }

    func refreshPasteAccess() {
        pasteAllowed = accessibilityAllowed()
    }

    /// What choosing an item does now. Checks Accessibility afresh.
    func pasteOutcome(hasPreviousApp: Bool) -> PasteOutcome {
        refreshPasteAccess()
        return PastePlanner.outcome(
            pasteDirectly: pasteDirectly, accessAllowed: pasteAllowed,
            hasPreviousApp: hasPreviousApp, accessRequestedBefore: settings.accessRequested
        )
    }

    /// The system's Accessibility request has been shown; it is not shown again from the window.
    func markAccessRequested() {
        settings.accessRequested = true
    }

    func refreshAccessState() {
        if #available(macOS 15.4, *) {
            switch pasteboard.accessBehavior {
            case .ask, .alwaysDeny:
                accessBlocked = true
            default:
                accessBlocked = false
            }
        } else {
            accessBlocked = false
        }
    }

    // MARK: - Actions

    /// How many items Clear would remove now, for the confirmation.
    var clearCount: Int {
        RetentionPolicy.itemsToRemoveOnClear(from: items, keep: clearKeep).count
            + CaptureRetention.toRemoveOnClear(captures, keep: clearKeep).count
    }

    /// Clears history, keeping what the Clear setting says.
    func clear() {
        enqueue { store in
            try await store.clear(keeping: self.clearKeep)
        }
    }

    /// Puts an item back on the clipboard and moves it to the top. Returns false if it could
    /// not be read.
    func copyBack(_ item: ClipItem) async -> Bool {
        guard let store else { return false }
        do {
            let content = try await store.content(for: item.id)
            let changeCount = PasteboardReader.write(content, to: pasteboard)
            ownWriteChangeCounts.insert(changeCount)
            enqueue { store in
                try await store.markUsed(item.id)
            }
            return true
        } catch {
            problem = "That item could not be read back."
            await reloadItems()
            return false
        }
    }

    /// Pins or unpins. A refused pin leaves a notice for the window.
    func togglePin(_ item: ClipItem) {
        notice = nil
        enqueue { store in
            let outcome = item.pinned ? try await store.unpin(item.id) : try await store.pin(item.id)
            if outcome == .pinRefused {
                self.notice = "Not pinned: pinned items alone would go over the storage limit."
            }
        }
    }

    func clearNotice() {
        notice = nil
    }

    func delete(_ item: ClipItem) {
        notice = nil
        enqueue { store in
            try await store.delete(item.id)
        }
    }

    /// Ids of the items matching `query`, most recently used first (C3 plan, decision 3).
    func search(_ query: String) async -> [UUID] {
        guard let store else { return [] }
        return (try? await store.search(query)) ?? []
    }

    /// The full content of an item for the preview pane; nil if it cannot be read.
    func previewContent(for item: ClipItem) async -> ClipContent? {
        guard let store else { return nil }
        return try? await store.content(for: item.id)
    }

#if DEBUG
    /// Debug hook only: adds test content as if copied in `sourceApp`, without the clipboard.
    func debugAdd(_ content: ClipContent, sourceApp: String?, at date: Date = Date()) {
        enqueue { store in
            try await store.add(content, sourceApp: sourceApp, now: date)
        }
    }
#endif

    /// Frees the store's search index (the window closed).
    func releaseSearchIndex() {
        guard let store else { return }
        Task { await store.releaseSearchIndex() }
    }

    func imageFileURL(for item: ClipItem) async -> URL? {
        guard let store else { return nil }
        return try? await store.imageFileURL(for: item.id)
    }

    // MARK: - On and off

    private func turnOn() {
        // Switched off and on again before the store closed: keep using the open one, so two
        // stores never share the folder.
        if store == nil {
            do {
                let directory = try storeDirectory ?? ClipboardStore.defaultDirectory()
                store = try ClipboardStore(directory: directory, limits: settings.limits)
                problem = nil
            } catch {
                store = nil
                isEnabled = false
                // The switch shows off, so the saved choice says off too.
                settings.historyEnabled = false
                problem = "Clipboard history could not open its storage: \(error)"
                return
            }
        }
        isEnabled = true
        refreshAccessState()
        enqueue { store in
            try await store.applyRetention()
        }
        retentionTimer = Timer.scheduledTimer(withTimeInterval: Self.retentionInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.enqueue { store in try await store.applyRetention() }
            }
        }
        if !isPaused {
            startWatching()
        }
    }

    /// Stops recording. What is already stored stays until Clear (decided 23 November 2026).
    private func turnOff() {
        stopWatching()
        retentionTimer?.invalidate()
        retentionTimer = nil
        isEnabled = false
        // Close the store after the work already queued, as part of the same queue, so a quick
        // switch back on either reuses it or opens a new one strictly afterwards.
        let previous = pendingWork
        pendingWork = Task {
            await previous?.value
            guard !self.isEnabled else { return }
            self.store = nil
            self.items = []
            self.captures = []
        }
    }

    // MARK: - Watching

    private func startWatching() {
        stopWatching()
        // Only copies made from now on are recorded, not what was already on the clipboard.
        lastChangeCount = pasteboard.changeCount
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        pollTimer?.tolerance = 0.1
    }

    private func stopWatching() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Checks the pasteboard once. The timer calls this; tests call it directly.
    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        let change = PasteboardReader.change(
            of: pasteboard,
            frontmostBundleID: frontmostApp?() ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        let decision = rules.decide(
            change, historyEnabled: isEnabled, paused: isPaused, ownWriteChangeCounts: ownWriteChangeCounts
        )
        ownWriteChangeCounts = ownWriteChangeCounts.filter { $0 > count }
        guard decision == .record, let content = PasteboardReader.content(from: pasteboard) else { return }

        let sourceApp = change.frontmostBundleID
        enqueue { store in
            let normalized = await Task.detached(priority: .utility) {
                PasteboardReader.normalized(content)
            }.value
            try await store.add(normalized, sourceApp: sourceApp)
        }
    }

    // MARK: - Store work

    private func enqueue(_ work: @escaping @MainActor (ClipboardStore) async throws -> Void) {
        guard let store else { return }
        let previous = pendingWork
        pendingWork = Task {
            await previous?.value
            do {
                try await work(store)
                self.problem = nil
            } catch {
                self.problem = "Clipboard history could not save a change: \(error)"
            }
            await self.reloadItems()
        }
    }

    /// Waits until every queued store change has finished (for tests and orderly shutdown).
    func waitUntilIdle() async {
        while let work = pendingWork {
            await work.value
            if pendingWork == work { break }
        }
    }

    private func reloadItems() async {
        guard let store else {
            items = []
            captures = []
            return
        }
        items = await store.items
        captures = await store.captures
    }

    // MARK: - Captures (C4)

    /// Whether new captures are kept: only while history is on and not paused (C4 plan, 2).
    var keepsCaptures: Bool { store != nil && isEnabled && !isPaused }

    /// Keeps a new screenshot. Returns its Captures id, or nil when captures are not kept.
    func recordScreenshot(_ image: CGImage) async -> UUID? {
        guard keepsCaptures, let store else { return nil }
        let width = image.width, height = image.height
        let png = await Task.detached(priority: .utility) { Self.pngData(image) }.value
        guard let png else { return nil }
        do {
            let id = try await store.addScreenshot(png: png, pixelWidth: width, pixelHeight: height)
            await reloadItems()
            return id
        } catch {
            problem = "Captures could not keep that screenshot: \(error)"
            return nil
        }
    }

    /// The editor closed: keep its marks and crop with the screenshot.
    func updateCaptureState(_ id: UUID, _ state: CaptureEditorState) {
        guard let data = state.encoded() else { return }
        enqueue { store in
            try await store.updateCaptureAnnotations(id, data)
        }
    }

    /// A recording was saved: keep where, by path only.
    func recordSavedRecording(_ url: URL, pixelSize: CGSize) {
        guard keepsCaptures else { return }
        enqueue { store in
            try await store.addRecordingReference(
                path: url.path, pixelWidth: Int(pixelSize.width), pixelHeight: Int(pixelSize.height)
            )
        }
    }

    func deleteCapture(_ capture: CaptureItem) {
        enqueue { store in
            try await store.deleteCapture(capture.id)
        }
    }

    func captureImageURL(_ capture: CaptureItem) async -> URL? {
        guard let store else { return nil }
        return await store.captureImageURL(capture.id)
    }

    /// The screenshot and its saved marks, for reopening, copying or saving.
    func captureContents(_ capture: CaptureItem) async -> (image: CGImage, state: CaptureEditorState)? {
        guard let store, let url = await store.captureImageURL(capture.id),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let state = CaptureEditorState.decoded(try? await store.captureAnnotations(capture.id)) ?? CaptureEditorState()
        return (image, state)
    }

    /// The screenshot with its marks, as the editor would export it at native size.
    func renderedCapture(_ capture: CaptureItem) async -> Data? {
        guard let contents = await captureContents(capture) else { return nil }
        let result = await ExportService.shared.exportPNGResult(
            baseImage: contents.image,
            annotations: contents.state.annotations,
            cropRect: contents.state.cropRect,
            exportSize: .native
        )
        if case .success(let data) = result { return data }
        return nil
    }

    nonisolated static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
