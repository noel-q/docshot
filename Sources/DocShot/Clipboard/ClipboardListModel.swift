import AppKit
import Combine
import ClipboardKit
import Foundation

/// What a key press in the window does (C3 plan, decisions 1 and 4).
enum ClipboardKeyAction: Equatable {
    case close, clearSearch, up, down, choose, copy, togglePin, delete
    /// Cmd+1 to Cmd+9: paste that row (restyle plan, decision 2). One-based.
    case pick(Int)
    /// Cmd+Y: show or hide the preview pane (compact panels, decision 3).
    case togglePreview
    /// Tab: between Clipboard and Captures (C4 plan, decision 4).
    case switchSection
    /// Shift+Cmd+C: copy the text found in an image (C4a).
    case copyText
    /// Not ours: the search field gets it.
    case passThrough
}

enum ClipboardKeys {
    static let escape: UInt16 = 53, up: UInt16 = 126, down: UInt16 = 125
    static let returnKey: UInt16 = 36, enter: UInt16 = 76, delete: UInt16 = 51, tab: UInt16 = 48
    /// ANSI positions of C, P and Y, used only when the layout gives no Latin letter (Russian, Greek).
    static let ansiC: UInt16 = 8, ansiP: UInt16 = 35, ansiY: UInt16 = 16
    /// ANSI digit row, 1 to 9, used when the layout types something else there (AZERTY).
    static let ansiDigits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

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
        case (tab, []): return .switchSection
        default: break
        }
        if flags == [.command, .shift],
           commandLetter(keyCode: keyCode, characters: characters, charactersIgnoringModifiers: charactersIgnoringModifiers) == "c" {
            return .copyText
        }
        guard flags == [.command] else { return .passThrough }
        if let digit = commandDigit(keyCode: keyCode, characters: characters) {
            return .pick(digit)
        }
        switch commandLetter(keyCode: keyCode, characters: characters, charactersIgnoringModifiers: charactersIgnoringModifiers) {
        case "c": return hasTextSelection ? .passThrough : .copy
        case "p": return .togglePin
        case "y": return .togglePreview
        default: return .passThrough
        }
    }

    /// 1 to 9 from the typed digit, or from the digit-row position when the layout types a
    /// symbol there (AZERTY types "&" for 1).
    static func commandDigit(keyCode: UInt16, characters: String?) -> Int? {
        if let text = characters, text.count == 1, let digit = Int(text), (1...9).contains(digit) {
            return digit
        }
        // A Latin letter is a letter shortcut, never a digit; anything else on the digit row
        // (AZERTY's "&", "é") counts by position.
        if let text = characters, text.count == 1, let first = text.first, first.isASCII, first.isLetter { return nil }
        return ansiDigits.firstIndex(of: keyCode).map { $0 + 1 }
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
        case ansiY: return "y"
        default: return nil
        }
    }
}

/// Size and place of the compact clipboard panel (compact panels, decisions 2 and 3). Pure
/// geometry in Cocoa screen coordinates, so it can be tested without a screen.
enum ClipboardPanelLayout {
    /// Search, list and key hints.
    static let listWidth: CGFloat = 420
    /// The preview pane that slides out to the right on Cmd+Y.
    static let previewWidth: CGFloat = 360
    static let height: CGFloat = 480

    static func width(showingPreview: Bool) -> CGFloat {
        showingPreview ? listWidth + previewWidth : listWidth
    }

    /// Where the panel opens: the remembered place, nudged fully on screen, if it is on this
    /// screen at all; otherwise centred across with its top a fifth of the way down (where
    /// Spotlight sits).
    static func frame(visible: CGRect, savedOrigin: CGPoint?, showingPreview: Bool) -> CGRect {
        let size = CGSize(width: width(showingPreview: showingPreview), height: height)
        if let savedOrigin {
            let saved = CGRect(origin: savedOrigin, size: size)
            if visible.intersects(saved) { return clamped(saved, within: visible) }
        }
        let origin = CGPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.maxY - visible.height / 5 - size.height).rounded()
        )
        return clamped(CGRect(origin: origin, size: size), within: visible)
    }

    /// The frame after widening or narrowing to `width`: the left edge stays where it was unless
    /// the panel would then run off the right of the screen, in which case it moves left. It
    /// only ever moves sideways.
    static func resized(_ frame: CGRect, toWidth width: CGFloat, within visible: CGRect) -> CGRect {
        var result = CGRect(x: frame.minX, y: frame.minY, width: width, height: frame.height)
        result.origin.x = min(max(result.minX, visible.minX), max(visible.maxX - result.width, visible.minX))
        return result
    }

    static func clamped(_ frame: CGRect, within visible: CGRect) -> CGRect {
        var result = frame
        result.origin.x = min(max(result.minX, visible.minX), max(visible.maxX - result.width, visible.minX))
        result.origin.y = min(max(result.minY, visible.minY), max(visible.maxY - result.height, visible.minY))
        return result
    }
}

/// The type filter at the top of the window (restyle plan, decision 2).
enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all, text, images, files, colours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .images: return "Images"
        case .files: return "Files"
        case .colours: return "Colours"
        }
    }

    func includes(_ kind: ClipKind) -> Bool {
        switch self {
        case .all: return true
        case .text: return kind == .text || kind == .richText
        case .images: return kind == .image
        case .files: return kind == .fileURLs
        case .colours: return kind == .colour
        }
    }
}

/// The list in groups: pinned, then used today, then earlier (restyle plan, decision 4).
struct ClipboardGroups: Equatable {
    var pinned: [ClipItem] = []
    var today: [ClipItem] = []
    var earlier: [ClipItem] = []

    var rows: [ClipItem] { pinned + today + earlier }
}

/// The pure list rules of the window (C3 plan, decisions 3 to 5; restyle plan 2 and 4).
enum ClipboardList {

    /// Pinned items first, then today's, then earlier ones, each most recently used first.
    /// `matching` nil shows everything; otherwise only those ids. `filter` keeps one kind.
    static func arrange(
        _ items: [ClipItem], matching: Set<UUID>?, filter: ClipboardFilter = .all,
        now: Date = Date(), calendar: Calendar = .current
    ) -> ClipboardGroups {
        let shown = items.filter { item in
            filter.includes(item.kind) && (matching.map { $0.contains(item.id) } ?? true)
        }
        var groups = ClipboardGroups()
        for item in shown {
            if item.pinned {
                groups.pinned.append(item)
            } else if calendar.isDate(item.lastUsedAt, inSameDayAs: now) {
                groups.today.append(item)
            } else {
                groups.earlier.append(item)
            }
        }
        return groups
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
    /// The type filter; back to All each time the window opens.
    @Published var filter: ClipboardFilter = .all {
        didSet {
            guard filter != oldValue else { return }
            arrange()
            selectedID = rows.first?.id
        }
    }
    @Published private(set) var groups = ClipboardGroups()
    @Published private(set) var selectedID: UUID?
    /// Clipboard or Captures; Clipboard each time the window opens (C4 plan, decision 4).
    @Published var section: PanelSection = .clipboard
    /// The selected screenshot or recording in Captures.
    @Published var selectedCaptureID: UUID?
    /// Bumped when the window opens, so the view puts focus in the search field.
    @Published private(set) var focusRequest = 0
    /// The preview pane is out (compact panels, decision 3); remembered between openings.
    @Published var showPreview: Bool {
        didSet { if showPreview != oldValue { panelSettings.showPreview = showPreview } }
    }
    private let panelSettings: ClipboardSettings

    let controller: ClipboardHistoryController
    private let searchDelay: Duration
    private var latestItems: [ClipItem]
    /// Ids matching the current search; nil when the search is blank.
    private var matches: Set<UUID>?
    private var searchTask: Task<Void, Never>?
    private var itemsSubscription: AnyCancellable?

    var rows: [ClipItem] { groups.rows }
    var pinned: [ClipItem] { groups.pinned }
    var others: [ClipItem] { groups.today + groups.earlier }

    /// Row `number` (1 to 9) as Cmd+number picks it, once any search has settled.
    func settledRow(_ number: Int) async -> ClipItem? {
        await waitForSearch()
        let rows = rows
        return rows.indices.contains(number - 1) ? rows[number - 1] : nil
    }
    var selectedItem: ClipItem? { rows.first { $0.id == selectedID } }
    var isSearching: Bool { !SearchText.terms(query).isEmpty }

    init(
        controller: ClipboardHistoryController,
        searchDelay: Duration = .milliseconds(120)
    ) {
        self.controller = controller
        self.searchDelay = searchDelay
        // The controller's preferences, so tests and debug runs never touch the real ones.
        self.panelSettings = controller.preferences
        showPreview = panelSettings.showPreview
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
        filter = .all
        matches = nil
        latestItems = controller.items
        arrange()
        selectedID = rows.first?.id
        section = .clipboard
        selectedCaptureID = nil
        focusRequest += 1
    }

    /// Captures in panel order: screenshots, then recordings.
    var captureOrder: [CaptureItem] {
        controller.captures.filter { $0.kind == .screenshot } + controller.captures.filter { $0.kind == .recording }
    }

    var selectedCapture: CaptureItem? {
        let order = captureOrder
        return order.first { $0.id == selectedCaptureID } ?? order.first
    }

    func switchSection() {
        section = section == .clipboard ? .captures : .clipboard
        if section == .captures, selectedCaptureID == nil || !captureOrder.contains(where: { $0.id == selectedCaptureID }) {
            selectedCaptureID = captureOrder.first?.id
        }
        if section == .clipboard { focusRequest += 1 }
    }

    func moveCaptureSelection(_ action: CaptureKeyAction) {
        let order = captureOrder
        let current = order.firstIndex { $0.id == selectedCaptureID }
        let screenshots = order.filter { $0.kind == .screenshot }.count
        if let index = CaptureGrid.move(current, action, screenshots: screenshots, total: order.count) {
            selectedCaptureID = order[index].id
        }
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
        groups = ClipboardList.arrange(latestItems, matching: matches, filter: filter)
        selectedID = ClipboardList.keepSelection(selectedID, old: old, new: rows)
    }

}

// MARK: - Captures (C4)

/// The panel's two sections (C4 plan, decision 4).
enum PanelSection: Equatable {
    case clipboard, captures
}

/// What a key does in Captures (C4 plan, decision 4). Pure, so the map is tested.
enum CaptureKeyAction: Equatable {
    case close, switchSection, left, right, up, down
    /// Return: a screenshot is copied with its marks and the panel closes; a recording is shown
    /// in Finder.
    case choose
    /// Cmd+C: copy the screenshot with its marks; the panel stays.
    case copy
    /// Cmd+E: open the screenshot in the editor with its marks.
    case edit
    /// Cmd+S: save the screenshot with its marks.
    case save
    /// Cmd+Delete.
    case delete
    case passThrough
}

enum CaptureKeys {
    static let left: UInt16 = 123, right: UInt16 = 124
    static let ansiE: UInt16 = 14, ansiS: UInt16 = 1

    static func action(
        keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?, charactersIgnoringModifiers: String?
    ) -> CaptureKeyAction {
        let flags = modifiers.intersection([.command, .option, .control, .shift])
        switch (keyCode, flags) {
        case (ClipboardKeys.escape, []): return .close
        case (ClipboardKeys.tab, []): return .switchSection
        case (left, []): return .left
        case (right, []): return .right
        case (ClipboardKeys.up, []): return .up
        case (ClipboardKeys.down, []): return .down
        case (ClipboardKeys.returnKey, []), (ClipboardKeys.enter, []): return .choose
        case (ClipboardKeys.delete, [.command]): return .delete
        default: break
        }
        guard flags == [.command] else { return .passThrough }
        let letter = ClipboardKeys.commandLetter(
            keyCode: keyCode, characters: characters, charactersIgnoringModifiers: charactersIgnoringModifiers
        )
        switch letter {
        case "c": return .copy
        case "e": return .edit
        case "s": return .save
        default:
            // Non-Latin layouts: E and S by position.
            if keyCode == ansiE { return .edit }
            if keyCode == ansiS { return .save }
            return .passThrough
        }
    }
}

/// Moving through Captures: screenshots in a grid of `columns`, then recordings one per row.
/// Indexes run over screenshots first, then recordings. Pure, so it is tested.
enum CaptureGrid {
    static let columns = 4

    static func move(_ index: Int?, _ action: CaptureKeyAction, screenshots: Int, total: Int) -> Int? {
        guard total > 0 else { return nil }
        guard let index else { return 0 }
        let inGrid = index < screenshots
        var target = index
        switch action {
        case .left: target = index - 1
        case .right: target = index + 1
        case .up:
            if inGrid { target = index - columns }
            else if index == screenshots, screenshots > 0 {
                // From the first recording up to the last row of screenshots.
                target = screenshots - 1
            } else { target = index - 1 }
        case .down:
            if inGrid {
                let below = index + columns
                // The last row of screenshots goes down to the first recording.
                target = below < screenshots ? below : (screenshots < total ? screenshots : index)
            } else { target = index + 1 }
        default: return index
        }
        return min(max(target, 0), total - 1)
    }
}
