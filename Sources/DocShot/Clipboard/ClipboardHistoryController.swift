import AppKit
import ClipboardKit
import Vision

/// Runs clipboard history in the app (plan sections 4.3 and C2): watches the general pasteboard
/// while history is on and not paused, saves copies through `ClipboardStore`, and copies items
/// back. With history off it watches nothing: no timer and no clipboard reads. The store opens
/// only to count or clear what was kept before (decided 25 November 2026), then closes again.
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
    /// What stays stored while history is off, so Clear can still remove it. Read at launch,
    /// when history is switched off and after a Clear; empty while history is on.
    @Published private(set) var storedItems: [ClipItem] = []
    @Published private(set) var storedCaptures: [CaptureItem] = []
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
        } else {
            readStoredWhileOff()
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

    /// How many items Clear would remove now, for the confirmation. With history off, counts
    /// what is still stored.
    var clearCount: Int {
        let keptItems = isEnabled ? items : storedItems
        let keptCaptures = isEnabled ? captures : storedCaptures
        return RetentionPolicy.itemsToRemoveOnClear(from: keptItems, keep: clearKeep).count
            + CaptureRetention.toRemoveOnClear(keptCaptures, keep: clearKeep).count
    }

    /// History is off but items or captures are still stored, so Clear is offered.
    var hasStoredWhileOff: Bool {
        !isEnabled && !(storedItems.isEmpty && storedCaptures.isEmpty)
    }

    /// Clears history, keeping what the Clear setting says. Works with history off too.
    func clear() {
        let keep = clearKeep
        if isEnabled {
            enqueue { store in
                try await store.clear(keeping: keep)
            }
        } else {
            withStoreWhileOff { store in
                try await store.clear(keeping: keep)
            }
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
            if case .image = content { self.recogniseWaitingImages() }
        }
    }

    /// Waits for the text reader to finish (debug hook).
    func debugWaitForRecognition() async {
        while let task = recognitionTask { await task.value }
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
        storedItems = []
        storedCaptures = []
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
        // Images kept before this version, or while DocShot was closed, are read now.
        recogniseWaitingImages()
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
            guard !self.isEnabled, let store = self.store else { return }
            // Remember what stays stored, so Clear can still reach it.
            let keptItems = await store.items
            let keptCaptures = await store.captures
            guard !self.isEnabled else { return }
            self.storedItems = keptItems
            self.storedCaptures = keptCaptures
            self.store = nil
            self.items = []
            self.captures = []
        }
    }

    /// Counts what is stored while history is off. Opens nothing if history was never kept.
    private func readStoredWhileOff() {
        withStoreWhileOff { _ in }
    }

    /// Runs `work` on the store while history is off: opens it only if history was ever kept
    /// (never creates an empty one), updates the stored counts, and closes it again. Queued
    /// with the other store work, and the open store is the controller's own, so switching
    /// history on meanwhile reuses it and two stores never share the folder.
    private func withStoreWhileOff(_ work: @escaping @MainActor (ClipboardStore) async throws -> Void) {
        let previous = pendingWork
        pendingWork = Task {
            await previous?.value
            guard let store = self.store ?? self.openStoredHistory() else {
                self.storedItems = []
                self.storedCaptures = []
                return
            }
            self.store = store
            do {
                try await work(store)
                self.problem = nil
            } catch {
                self.problem = "Clipboard history could not save a change: \(error)"
            }
            if self.isEnabled {
                await self.reloadItems()
                return
            }
            let keptItems = await store.items
            let keptCaptures = await store.captures
            guard !self.isEnabled else {
                await self.reloadItems()
                return
            }
            self.storedItems = keptItems
            self.storedCaptures = keptCaptures
            self.store = nil
        }
    }

    /// The store, if history was kept before; nil, creating nothing, if it never was.
    private func openStoredHistory() -> ClipboardStore? {
        do {
            let directory = try storeDirectory ?? ClipboardStore.defaultDirectory()
            let database = directory.appendingPathComponent(ClipboardStore.databaseName)
            guard FileManager.default.fileExists(atPath: database.path) else { return nil }
            return try ClipboardStore(directory: directory, limits: settings.limits)
        } catch {
            problem = "Stored clipboard history could not be opened: \(error)"
            return nil
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
            if case .image = normalized {
                self.recogniseWaitingImages()
            }
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

    // MARK: - Text in images (C4a)

    private var recognitionTask: Task<Void, Never>?

    /// Reads the text in stored images, one at a time, in the background at low priority, each
    /// image once (plan section 7). Only while history is on; nothing runs when there is nothing
    /// waiting, so idle costs nothing.
    func recogniseWaitingImages() {
        guard recognitionTask == nil, isEnabled, let store else { return }
        recognitionTask = Task(priority: .background) { @MainActor in
            var tried = Set<UUID>()
            while self.isEnabled, self.store === store,
                  let id = try? await store.imagesAwaitingText().first(where: { !tried.contains($0) }) {
                tried.insert(id)
                let url = try? await store.imageFileURL(for: id)
                let text = await Task.detached(priority: .background) {
                    url.flatMap(TextRecognition.text(in:))
                }.value
                // History turned off, or reopened, while reading: keep nothing.
                guard self.isEnabled, self.store === store else { break }
                // Unreadable images are marked read too, so they are not tried again. A failed
                // write stops the run; the next image or the next start tries again.
                do {
                    try await store.setRecognisedText(id, text ?? "")
                } catch {
                    break
                }
            }
            self.recognitionTask = nil
            await self.reloadItems()
        }
    }

    func recognisedText(for item: ClipItem) async -> String? {
        guard let store else { return nil }
        return try? await store.recognisedText(item.id)
    }

    /// Copy text: puts the text on the clipboard as DocShot's own write, so it is not
    /// recorded as a new item.
    func copyRecognisedText(_ text: String) {
        let changeCount = PasteboardReader.write(.text(text), to: pasteboard)
        ownWriteChangeCounts.insert(changeCount)
    }

    // MARK: - Captures (C4)

    /// Whether new captures are kept: only while history is on and not paused (C4 plan, 2).
    var keepsCaptures: Bool { store != nil && isEnabled && !isPaused }

    /// Keeps a new screenshot. Returns its Captures id, or nil when captures are not kept.
    func recordScreenshot(_ image: CGImage) async -> UUID? {
        guard keepsCaptures, let store else { return nil }
        let width = image.width, height = image.height
        let png = await Task.detached(priority: .utility) { Self.pngData(image) }.value
        // Turned off or paused while encoding: keep nothing.
        guard let png, keepsCaptures, self.store === store else { return nil }
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

/// Text in an image, read on this Mac by Vision (C4a). Nothing leaves the Mac.
enum TextRecognition {
    static func text(in url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            return nil
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
