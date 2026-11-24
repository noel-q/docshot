import AppKit
import ClipboardKit

/// Runs clipboard history in the app (plan sections 4.3 and C2): watches the general pasteboard
/// while history is on and not paused, saves copies through `ClipboardStore`, and copies items
/// back. With history off it does nothing at all: no timer, no store, no reads.
@MainActor
final class ClipboardHistoryController: ObservableObject {
    static let shared = ClipboardHistoryController()

    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var isEnabled = false
    @Published private(set) var isPaused = false
    @Published private(set) var clearKeep: ClearKeep = .defaultValue
    /// macOS asks before, or refuses, clipboard reads for DocShot (plan 4.3, C0 finding).
    @Published private(set) var accessBlocked = false
    /// The last problem worth showing in Settings, such as a store that would not open.
    @Published private(set) var problem: String?

    /// Polling interval (plan 4.3: about twice a second).
    static let pollInterval: TimeInterval = 0.5
    static let retentionInterval: TimeInterval = 60 * 60

    private let settings: ClipboardSettings
    private let pasteboard: NSPasteboard
    /// Nil means the real store folder; tests pass a temporary one.
    private let storeDirectory: URL?
    /// Nil means the real front app; tests pass a fixed one.
    private let frontmostApp: (() -> String?)?
    private let rules = RecordingRules()
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
        frontmostApp: (() -> String?)? = nil
    ) {
        self.settings = settings
        self.pasteboard = pasteboard
        self.storeDirectory = storeDirectory
        self.frontmostApp = frontmostApp
    }

    /// Called once at launch.
    func start() {
        clearKeep = settings.clearKeep
        isPaused = settings.paused
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
                store = try ClipboardStore(directory: directory)
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
            return
        }
        items = await store.items
    }
}
