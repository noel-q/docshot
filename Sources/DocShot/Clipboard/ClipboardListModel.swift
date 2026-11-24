import AppKit
import Combine
import ClipboardKit
import Foundation

/// What a key press in the window does (C3 plan, decisions 1 and 4).
enum ClipboardKeyAction: Equatable {
    case close, clearSearch, up, down, choose, copy, togglePin, delete
    /// Not ours: the search field gets it.
    case passThrough
}

enum ClipboardKeys {
    static let escape: UInt16 = 53, up: UInt16 = 126, down: UInt16 = 125
    static let returnKey: UInt16 = 36, enter: UInt16 = 76, delete: UInt16 = 51
    /// ANSI positions of C and P, used only when the layout gives no Latin letter (Russian, Greek).
    static let ansiC: UInt16 = 8, ansiP: UInt16 = 35

    static func action(
        keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?,
        charactersIgnoringModifiers: String?, hasMarkedText: Bool, hasTextSelection: Bool, queryIsEmpty: Bool
    ) -> ClipboardKeyAction {
        // Typing with an input method: Return, Escape and arrows belong to the candidate window.
        if hasMarkedText { return .passThrough }
        let flags = modifiers.intersection([.command, .option, .control, .shift])
        switch (keyCode, flags) {
        case (escape, []): return queryIsEmpty ? .close : .clearSearch
        case (up, []): return .up
        case (down, []): return .down
        case (returnKey, []), (enter, []): return .choose
        case (delete, [.command]): return .delete
        default: break
        }
        guard flags == [.command] else { return .passThrough }
        switch commandLetter(keyCode: keyCode, characters: characters, charactersIgnoringModifiers: charactersIgnoringModifiers) {
        case "c": return hasTextSelection ? .passThrough : .copy
        case "p": return .togglePin
        default: return .passThrough
        }
    }

    /// The Latin letter typed with Command: from the layout when it gives one, otherwise from
    /// the key position, so the shortcuts work on non-Latin layouts too.
    static func commandLetter(keyCode: UInt16, characters: String?, charactersIgnoringModifiers: String?) -> String? {
        for text in [characters, charactersIgnoringModifiers] {
            guard let text = text?.lowercased(), text.count == 1, let scalar = text.unicodeScalars.first else { continue }
            if scalar.isASCII { return scalar.properties.isAlphabetic ? text : nil }
        }
        switch keyCode {
        case ansiC: return "c"
        case ansiP: return "p"
        default: return nil
        }
    }
}

/// The pure list rules of the window (C3 plan, decisions 3 to 5).
enum ClipboardList {

    /// Pinned items first, then the rest, each most recently used first. `matching` nil shows
    /// everything; otherwise only those ids.
    static func arrange(_ items: [ClipItem], matching: Set<UUID>?) -> (pinned: [ClipItem], others: [ClipItem]) {
        let shown = matching.map { ids in items.filter { ids.contains($0.id) } } ?? items
        return (shown.filter(\.pinned), shown.filter { !$0.pinned })
    }

    /// One step up (-1) or down (+1), stopping at the ends. With nothing selected, the first row.
    static func move(_ selected: UUID?, by step: Int, in rows: [ClipItem]) -> UUID? {
        guard !rows.isEmpty else { return nil }
        guard let selected, let index = rows.firstIndex(where: { $0.id == selected }) else {
            return rows.first?.id
        }
        return rows[min(max(index + step, 0), rows.count - 1)].id
    }

    /// Keeps the selection when the list changes. If the selected row went (deleted, or no
    /// longer matching), the row now at its place is selected, so deleting in a row is quick.
    static func keepSelection(_ selected: UUID?, old: [ClipItem], new: [ClipItem]) -> UUID? {
        guard !new.isEmpty else { return nil }
        guard let selected else { return new.first?.id }
        if new.contains(where: { $0.id == selected }) { return selected }
        guard let oldIndex = old.firstIndex(where: { $0.id == selected }) else { return new.first?.id }
        return new[min(oldIndex, new.count - 1)].id
    }
}

/// What the window shows: the search text, the arranged rows and the selection.
@MainActor
final class ClipboardWindowModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    @Published private(set) var pinned: [ClipItem] = []
    @Published private(set) var others: [ClipItem] = []
    @Published private(set) var selectedID: UUID?
    /// Bumped when the window opens, so the view puts focus in the search field.
    @Published private(set) var focusRequest = 0

    let controller: ClipboardHistoryController
    private let searchDelay: Duration
    private var latestItems: [ClipItem]
    /// Ids matching the current search; nil when the search is blank.
    private var matches: Set<UUID>?
    private var searchTask: Task<Void, Never>?
    private var itemsSubscription: AnyCancellable?

    var rows: [ClipItem] { pinned + others }
    var selectedItem: ClipItem? { rows.first { $0.id == selectedID } }
    var isSearching: Bool { !SearchText.terms(query).isEmpty }

    init(controller: ClipboardHistoryController, searchDelay: Duration = .milliseconds(120)) {
        self.controller = controller
        self.searchDelay = searchDelay
        latestItems = controller.items
        arrange()
        itemsSubscription = controller.$items.sink { [weak self] items in
            MainActor.assumeIsolated {
                self?.itemsChanged(items)
            }
        }
    }

    /// The window opened: blank search, first row selected, focus in the field.
    func reset() {
        searchTask?.cancel()
        query = ""
        matches = nil
        latestItems = controller.items
        arrange()
        selectedID = rows.first?.id
        focusRequest += 1
    }

    func moveSelection(by step: Int) {
        selectedID = ClipboardList.move(selectedID, by: step, in: rows)
    }

    func select(_ id: UUID) {
        selectedID = id
    }

    /// Waits until no search is pending, including one a clipboard change started meanwhile.
    func waitForSearch() async {
        while let task = searchTask {
            await task.value
            if searchTask == task { break }
        }
    }

    /// The window closed: stop any search, so it cannot rebuild the index afterwards.
    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
    }

    /// The selection once any search in progress has settled, so a key pressed straight after
    /// typing acts on the list the user is about to see, not the one before.
    func settledSelection() async -> ClipItem? {
        await waitForSearch()
        return selectedItem
    }

    private func itemsChanged(_ items: [ClipItem]) {
        latestItems = items
        if isSearching {
            // A new copy or a removal changes what matches: search again at once.
            runSearch(query, delay: .zero, selectFirst: false)
        } else {
            arrange()
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        guard isSearching else {
            matches = nil
            arrange()
            selectedID = rows.first?.id
            return
        }
        runSearch(query, delay: searchDelay, selectFirst: true)
    }

    /// `selectFirst`: new search text selects the best match; a list change keeps the selection.
    private func runSearch(_ text: String, delay: Duration, selectFirst: Bool) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard let self, !Task.isCancelled else { return }
            let ids = await self.controller.search(text)
            guard !Task.isCancelled, text == self.query else { return }
            self.matches = Set(ids)
            self.arrange()
            if selectFirst {
                self.selectedID = self.rows.first?.id
            }
        }
    }

    private func arrange() {
        let old = rows
        let arranged = ClipboardList.arrange(latestItems, matching: matches)
        pinned = arranged.pinned
        others = arranged.others
        selectedID = ClipboardList.keepSelection(selectedID, old: old, new: rows)
    }
}
