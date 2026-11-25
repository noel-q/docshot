import AppKit
import ClipboardKit
import ImageIO
import SwiftUI

/// The clipboard window in Quiet (restyle plan, 24 November 2026; Quiet `ClipboardWindow`):
/// a bare search bar with the type filter, the list on `canvas` with a sliding neutral
/// selection, the preview pane on `surface`, and a key-hint footer. Behaviour is C3's.
struct ClipboardHistoryView: View {
    /// Redraws this view when the colour theme changes (C0.7); the accent follows it.
    @ObservedObject var themeController = ThemeController.shared
    @ObservedObject var model: ClipboardWindowModel
    @ObservedObject var controller: ClipboardHistoryController
    let onChoose: (ClipItem) -> Void
    let onClose: () -> Void

    @State private var confirmingClear = false
    @FocusState private var searchFocused: Bool
    @Namespace private var selectionSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var listWidth: CGFloat { ClipboardPanelLayout.listWidth }
    let onTogglePreview: () -> Void
    /// A click or double-click in Captures (C4).
    var onCaptureAction: (CaptureKeyAction, CaptureItem) -> Void = { _, _ in }

    var body: some View {
        VStack(spacing: 0) {
            if controller.isEnabled {
                sectionTabs
            }
            if controller.isEnabled && model.section == .captures {
                Rectangle().fill(Quiet.line).frame(height: 1)
                CapturesSectionView(model: model, controller: controller, onAction: onCaptureAction)
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(Quiet.line).frame(height: 1)
                capturesFooter
            } else if controller.isEnabled {
                topBar
                if controller.isPaused {
                    pausedLine
                }
                Rectangle().fill(Quiet.line).frame(height: 1)
                // The list keeps its width; the preview pane sits to its right and is revealed as
                // the panel widens (compact panels, decision 3).
                HStack(spacing: 0) {
                    list
                        .frame(width: Self.listWidth)
                    if model.showPreview {
                        HStack(spacing: 0) {
                            Rectangle().fill(Quiet.line).frame(width: 1)
                            ClipPreviewPane(item: model.selectedItem, controller: controller)
                                .frame(width: ClipboardPanelLayout.previewWidth - 1)
                        }
                        .transition(.opacity.animation(Quiet.Motion.fade))
                    }
                }
                // minWidth 0: the content never insists on a width, so the panel's animated
                // edge clips the list and pane instead of the content forcing the panel wide.
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .clipped()
                Rectangle().fill(Quiet.line).frame(height: 1)
                footer
            } else {
                offState
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        // The panel's own shape (compact panels, decision 1): radius-lg, surface, hairline edge.
        .background(Quiet.surface)
        .clipShape(RoundedRectangle(cornerRadius: Quiet.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Quiet.Radius.lg, style: .continuous).strokeBorder(Quiet.line, lineWidth: 1)
        )
        .ignoresSafeArea()
        .tint(Quiet.accent)
        .onChange(of: model.focusRequest) { _, _ in searchFocused = true }
        .onAppear { searchFocused = true }
        .confirmationDialog(ClipboardSettings.clearQuestion(controller.clearCount), isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) { controller.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps \(controller.clearKeep.title.lowercased()). \(ClipboardSettings.clearWarning)")
        }
    }

    // MARK: - Sections (C4)

    /// Clipboard and Captures, with Tab to switch. Neutral selection: `selection` behind.
    private var sectionTabs: some View {
        HStack(spacing: Quiet.Space.s1) {
            tabButton("Clipboard", .clipboard)
            tabButton("Captures", .captures)
            Spacer(minLength: 0)
            Button { model.switchSection() } label: {
                hint("tab", "Switch")
            }
            .buttonStyle(.plain)
            .help("Switch between Clipboard and Captures (Tab)")
        }
        .font(Quiet.Font.caption)
        .padding(.horizontal, Quiet.Space.s3)
        .padding(.top, Quiet.Space.s2)
        .padding(.bottom, Quiet.Space.s1)
    }

    private func tabButton(_ title: String, _ section: PanelSection) -> some View {
        let selected = model.section == section
        return Button {
            if !selected { model.switchSection() }
        } label: {
            Text(title)
                .font(Quiet.Font.ui)
                .foregroundStyle(selected ? Quiet.ink : Quiet.inkMuted)
                .padding(.horizontal, Quiet.Space.s2)
                .padding(.vertical, Quiet.Space.s1)
                .background(
                    RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous)
                        .fill(selected ? Quiet.selection : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var capturesFooter: some View {
        HStack(spacing: Quiet.Space.s4) {
            if let problem = controller.problem {
                Text(problem).foregroundStyle(Quiet.danger).lineLimit(1)
            } else if let capture = model.selectedCapture {
                if capture.kind == .screenshot {
                    hint("↵", "Copy")
                    hint("⌘E", "Edit")
                    hint("⌘S", "Save")
                } else {
                    hint("↵", "Show in Finder")
                }
            }
            Spacer(minLength: 0)
            closeHint
        }
        .font(Quiet.Font.caption)
        .padding(.horizontal, Quiet.Space.s4)
        .frame(height: 36)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Quiet.Space.s3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Quiet.inkMuted)
                .accessibilityHidden(true)
            TextField("Search clipboard", text: $model.query)
                .textFieldStyle(.plain)
                .font(Quiet.Font.body)
                .foregroundStyle(Quiet.ink)
                .focused($searchFocused)
                .accessibilityLabel("Search clipboard")
            // A compact menu: the five-way segmented control does not fit beside the search at
            // the panel's 420 points.
            // Draws its own label in Quiet's colours: a tinted menu-style picker is drawn with
            // pale text that all but vanishes in light mode.
            Menu {
                Picker("Show", selection: $model.filter) {
                    ForEach(ClipboardFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: Quiet.Space.s1) {
                    Text(model.filter.title)
                        .font(Quiet.Font.ui)
                        .foregroundStyle(Quiet.ink)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Quiet.inkMuted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Quiet.Space.s2)
                .padding(.vertical, Quiet.Space.s1)
                .background(RoundedRectangle(cornerRadius: Quiet.Radius.xs, style: .continuous).fill(Quiet.surfaceRaised))
                .contentShape(Rectangle())
            }
            // Plain button menu: the label is drawn exactly as written (the borderless style
            // tints its icon with the accent and drops the background).
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Show one kind of item")
            .accessibilityLabel("Show: \(model.filter.title)")
            Menu {
                Button(controller.isPaused ? "Resume history" : "Pause history") {
                    controller.setPaused(!controller.isPaused)
                }
                Button("Clear history…") { confirmingClear = true }
                    .disabled(controller.clearCount == 0)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Quiet.inkMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(Quiet.inkMuted) // not the accent: it is not the main action
            .fixedSize()
            .help("History options")
            .accessibilityLabel("History options")
        }
        .padding(.horizontal, Quiet.Space.s4)
        .frame(height: 48)
    }

    private var pausedLine: some View {
        HStack(spacing: Quiet.Space.s2) {
            Text("History is paused. New copies are not recorded.")
                .font(Quiet.Font.caption)
                .foregroundStyle(Quiet.inkMuted)
            Button("Resume") { controller.setPaused(false) }
                .buttonStyle(.plain)
                .font(Quiet.Font.caption.weight(.medium))
                .foregroundStyle(Quiet.accent)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Quiet.Space.s4)
        .padding(.bottom, Quiet.Space.s2)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if controller.items.isEmpty {
            emptyState(
                title: controller.isPaused ? "History is paused" : "Nothing copied yet",
                detail: controller.isPaused
                    ? "Copies are not recorded until you resume."
                    : "Copy something in any app and it appears here."
            )
        } else if model.rows.isEmpty {
            emptyState(
                title: "No matches",
                detail: model.filter == .all
                    ? "Nothing in history matches. Images are searched by the text in them."
                    : "Nothing in \(model.filter.title.lowercased()) matches. Choose All to see everything."
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        section("Pinned", model.groups.pinned, offset: 0)
                        section("Today", model.groups.today, offset: model.groups.pinned.count)
                        section("Earlier", model.groups.earlier,
                                offset: model.groups.pinned.count + model.groups.today.count)
                    }
                    .padding(.horizontal, Quiet.Space.s2)
                    .padding(.bottom, Quiet.Space.s2)
                    .animation(reduceMotion ? nil : Quiet.Motion.fast, value: model.selectedID)
                }
                .onChange(of: model.selectedID) { _, id in
                    guard let id else { return }
                    if reduceMotion {
                        proxy.scrollTo(id)
                    } else {
                        withAnimation(Quiet.Motion.fast) { proxy.scrollTo(id) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [ClipItem], offset: Int) -> some View {
        if !items.isEmpty {
            Text(title)
                .font(Quiet.Font.label)
                .foregroundStyle(Quiet.inkMuted)
                .padding(.horizontal, Quiet.Space.s2)
                .padding(.top, Quiet.Space.s3)
                .padding(.bottom, Quiet.Space.s1)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let number = offset + index + 1
                ClipRowView(
                    item: item,
                    controller: controller,
                    selected: item.id == model.selectedID,
                    shortcutNumber: number <= 9 ? number : nil,
                    selectionSpace: selectionSpace,
                    onChoose: {
                        model.select(item.id)
                        onChoose(item)
                    }
                )
                .id(item.id)
            }
        }
    }

    private func emptyState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Quiet.Space.s2) {
            Text(title)
                .font(Quiet.Font.title3)
                .foregroundStyle(Quiet.ink)
            Text(detail)
                .font(Quiet.Font.body)
                .foregroundStyle(Quiet.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, Quiet.Space.s4)
        .padding(.top, Quiet.Space.s12)
    }

    // MARK: - Off

    private var offState: some View {
        VStack(alignment: .leading, spacing: Quiet.Space.s3) {
            Text("Clipboard history is off")
                .font(Quiet.Font.title3)
                .foregroundStyle(Quiet.ink)
            Text("When it is on, DocShot keeps what you copy on this Mac only. Copies from password managers are skipped.")
                .font(Quiet.Font.body)
                .foregroundStyle(Quiet.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340, alignment: .leading)
            HStack(spacing: Quiet.Space.s2) {
                // No Return shortcut: turning history on starts recording, so it takes a click.
                Button { controller.setEnabled(true) } label: {
                    AccentButtonLabel("Turn on")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, Quiet.Space.s2)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                closeHint
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, Quiet.Space.s8)
        .padding(.top, Quiet.Space.s12)
        .padding(.bottom, Quiet.Space.s3)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Quiet.Space.s4) {
            if let problem = controller.problem {
                Text(problem).foregroundStyle(Quiet.danger).lineLimit(1)
            } else if let notice = controller.notice {
                Text(notice).foregroundStyle(Quiet.warning).lineLimit(1)
            } else if model.selectedItem != nil {
                hint("↵", pastes ? "Paste" : "Copy")
                Button(action: onTogglePreview) {
                    hint("⌘Y", model.showPreview ? "Hide preview" : "Preview")
                }
                .buttonStyle(.plain)
                .help(model.showPreview ? "Hide the preview (⌘Y)" : "Show the preview (⌘Y)")
                hint("⌘P", model.selectedItem?.pinned == true ? "Unpin" : "Pin")
                // The Accessibility note lives in Settings (Clipboard, Pasting): the compact
                // footer has room for the hints only; "↵ Copy" already says paste is off.
            }
            Spacer(minLength: 0)
            closeHint
        }
        .font(Quiet.Font.caption)
        .padding(.horizontal, Quiet.Space.s4)
        .frame(height: 36)
    }

    private var pastes: Bool { controller.pasteDirectly && controller.pasteAllowed }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: Quiet.Space.s1) {
            KeyHint(keys: keys)
            Text(label).foregroundStyle(Quiet.inkFaint).lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    /// "esc Close", clickable too, since the window has no title bar buttons.
    private var closeHint: some View {
        Button(action: onClose) {
            hint("esc", "Close")
        }
        .buttonStyle(.plain)
        .help("Close (esc)")
        .accessibilityLabel("Close")
    }
}

/// A small key cap (Quiet `KeyHint`).
struct KeyHint: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(Quiet.Font.caption.monospacedDigit())
            .foregroundStyle(Quiet.inkMuted)
            .padding(.horizontal, Quiet.Space.s1)
            .frame(minWidth: 20, minHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: Quiet.Radius.xs, style: .continuous)
                    .fill(Quiet.controlSurface)
                    // shadow-control: a 1 px ring (light) and a 1 px drop.
                    .overlay(RoundedRectangle(cornerRadius: Quiet.Radius.xs, style: .continuous)
                        .stroke(Quiet.controlRing, lineWidth: 1))
                    .shadow(color: Quiet.controlDrop, radius: 1, y: 1)
            )
            .accessibilityLabel(Self.spoken(keys))
    }

    /// Symbols VoiceOver does not read well, as words.
    static func spoken(_ keys: String) -> String {
        switch keys {
        case "↵": return "Return"
        case "esc": return "Escape"
        case "↑ ↓": return "Up and down arrows"
        default: return keys
        }
    }
}

/// One history row (Quiet `ListRow`): 44 points, a 32-point preview, a title, one line of
/// "Source · time", and a trailing Cmd+number that shows on hover and selection, with pin and
/// delete buttons beside it under the pointer. A click pastes (C3 plan, decision 1).
private struct ClipRowView: View {
    @ObservedObject var themeController = ThemeController.shared
    let item: ClipItem
    let controller: ClipboardHistoryController
    let selected: Bool
    let shortcutNumber: Int?
    let selectionSpace: Namespace.ID
    let onChoose: () -> Void

    @State private var thumbnail: NSImage?
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Quiet.Space.s3) {
            Button(action: onChoose) {
                HStack(spacing: Quiet.Space.s3) {
                    leading
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(Quiet.Font.ui)
                            .foregroundStyle(Quiet.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(ClipDescription.metadata(for: item))
                            .font(Quiet.Font.caption.monospacedDigit())
                            .foregroundStyle(Quiet.inkMuted)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.pinned ? "Pinned " : "")\(ClipDescription.kindName(item.kind)): \(title)")
            .accessibilityHint("Pastes this item into the app you were in")

            trailing
        }
        .padding(.horizontal, Quiet.Space.s2)
        .frame(height: 44)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous)
                    .fill(Quiet.selection)
                    .matchedGeometryEffect(id: "selection", in: selectionSpace)
            } else if hovering {
                RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous)
                    .fill(Quiet.hover)
            }
        }
        .onHover { inside in
            withAnimation(reduceMotion ? nil : Quiet.Motion.instant) { hovering = inside }
        }
        .task(id: item.id) {
            guard item.kind == .image, thumbnail == nil,
                  let url = await controller.imageFileURL(for: item) else { return }
            thumbnail = await ThumbnailLoader.thumbnail(for: url, maxPixelSize: 96)
        }
    }

    /// The Cmd+number shows on hover and selection (Quiet `ListRow`); under the pointer the
    /// pin and delete buttons sit beside it.
    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 0) {
            if hovering {
                rowButton(item.pinned ? "pin.slash" : "pin", help: item.pinned ? "Unpin (⌘P)" : "Pin (⌘P)") {
                    controller.togglePin(item)
                }
                rowButton("trash", help: "Delete (⌘⌫)") {
                    controller.delete(item)
                }
            }
            if (hovering || selected), let shortcutNumber {
                KeyHint(keys: "⌘\(shortcutNumber)")
                    .padding(.leading, Quiet.Space.s1)
                    .accessibilityLabel("Command \(shortcutNumber)")
            }
        }
        .transition(.opacity)
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Quiet.inkMuted)
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder
    private var leading: some View {
        let shape = RoundedRectangle(cornerRadius: Quiet.Radius.xs, style: .continuous)
        if item.kind == .image, let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipShape(shape)
                .overlay(shape.stroke(Quiet.line, lineWidth: 1))
        } else if item.kind == .colour {
            shape
                .fill(Color(hex: item.preview) ?? Quiet.line)
                .overlay(shape.stroke(Quiet.line, lineWidth: 1))
        } else {
            Image(systemName: ClipDescription.symbol(for: item))
                .font(.system(size: 16))
                .foregroundStyle(Quiet.inkMuted)
                .frame(width: 32, height: 32)
                .background(shape.fill(Quiet.surfaceRaised))
        }
    }

    private var title: String {
        switch item.kind {
        case .image: return "Image"
        default: return item.preview.isEmpty ? "Empty text" : item.preview
        }
    }
}

/// Downsampled thumbnails, decoded off the main thread and cached for the session.
@MainActor
enum ThumbnailLoader {
    /// Keyed by file and size, so a row's small thumbnail is never reused for the preview.
    private static let cache = NSCache<NSString, NSImage>()

    static func thumbnail(for url: URL, maxPixelSize: Int) async -> NSImage? {
        let key = "\(url.path)#\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let cgImage = await Task.detached(priority: .utility) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        cache.setObject(image, forKey: key)
        return image
    }
}

extension Color {
    /// `#RRGGBB` or `#RRGGBBAA`, as `ClipColour.hexString` writes it.
    init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        let digits = String(hex.dropFirst())
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Captures section (C4)

/// Recent screenshots as a grid of thumbnails, then saved recordings by name (C4 plan,
/// decision 4). Selection is neutral; a double-click opens a screenshot in the editor or shows
/// a recording in Finder.
struct CapturesSectionView: View {
    @ObservedObject var model: ClipboardWindowModel
    @ObservedObject var controller: ClipboardHistoryController
    let onAction: (CaptureKeyAction, CaptureItem) -> Void

    private var screenshots: [CaptureItem] { controller.captures.filter { $0.kind == .screenshot } }
    private var recordings: [CaptureItem] { controller.captures.filter { $0.kind == .recording } }
    private var selectedID: UUID? { model.selectedCapture?.id }

    var body: some View {
        if controller.captures.isEmpty {
            VStack(alignment: .leading, spacing: Quiet.Space.s2) {
                Text(controller.isPaused ? "History is paused" : "No captures yet")
                    .font(Quiet.Font.title3)
                    .foregroundStyle(Quiet.ink)
                Text(controller.isPaused
                     ? "New screenshots are not kept until you resume."
                     : "Screenshots you take, and recordings you save, appear here.")
                    .font(Quiet.Font.body)
                    .foregroundStyle(Quiet.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, Quiet.Space.s4)
            .padding(.top, Quiet.Space.s12)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Quiet.Space.s2) {
                        if !screenshots.isEmpty {
                            heading("Screenshots")
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: Quiet.Space.s2), count: CaptureGrid.columns),
                                spacing: Quiet.Space.s2
                            ) {
                                ForEach(screenshots) { capture in
                                    CaptureThumbnailView(capture: capture, controller: controller, selected: capture.id == selectedID)
                                        .id(capture.id)
                                        .onTapGesture(count: 2) { onAction(.edit, capture) }
                                        .onTapGesture { model.selectedCaptureID = capture.id }
                                }
                            }
                        }
                        if !recordings.isEmpty {
                            heading("Recordings")
                            ForEach(recordings) { capture in
                                RecordingReferenceRow(capture: capture, selected: capture.id == selectedID)
                                    .id(capture.id)
                                    .onTapGesture(count: 2) { onAction(.choose, capture) }
                                    .onTapGesture { model.selectedCaptureID = capture.id }
                            }
                        }
                    }
                    .padding(.horizontal, Quiet.Space.s3)
                    .padding(.bottom, Quiet.Space.s3)
                }
                .onChange(of: model.selectedCaptureID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(Quiet.Font.label)
            .foregroundStyle(Quiet.inkMuted)
            .padding(.horizontal, Quiet.Space.s1)
            .padding(.top, Quiet.Space.s3)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One screenshot: its thumbnail and when it was taken.
private struct CaptureThumbnailView: View {
    let capture: CaptureItem
    @ObservedObject var controller: ClipboardHistoryController
    let selected: Bool
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: Quiet.Space.s1) {
            ZStack {
                RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous)
                    .fill(Quiet.canvas)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(Quiet.Space.s1)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous)
                    .strokeBorder(selected ? Quiet.ink : Quiet.line, lineWidth: selected ? 2 : 1)
            )
            Text(capture.createdAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                .font(Quiet.Font.caption)
                .foregroundStyle(Quiet.inkMuted)
                .lineLimit(1)
        }
        .padding(Quiet.Space.s1)
        .background(
            RoundedRectangle(cornerRadius: Quiet.Radius.md, style: .continuous)
                .fill(selected ? Quiet.selection : Color.clear)
        )
        .contentShape(Rectangle())
        .task(id: capture.id) {
            guard let url = await controller.captureImageURL(capture) else { return }
            image = await Task.detached(priority: .utility) { CaptureThumbnailView.thumbnail(url) }.value
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Screenshot, \(capture.pixelWidth) by \(capture.pixelHeight)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    nonisolated static func thumbnail(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

/// One saved recording: its file name and when it was saved; says so if the file has moved.
private struct RecordingReferenceRow: View {
    let capture: CaptureItem
    let selected: Bool

    private var exists: Bool { capture.filePath.map { FileManager.default.fileExists(atPath: $0) } ?? false }

    var body: some View {
        HStack(spacing: Quiet.Space.s3) {
            Image(systemName: "film")
                .font(Quiet.Font.ui)
                .foregroundStyle(Quiet.inkMuted)
                .frame(width: Quiet.Space.s6)
            VStack(alignment: .leading, spacing: 2) {
                Text(capture.filePath.map { ($0 as NSString).lastPathComponent } ?? "Recording")
                    .font(Quiet.Font.ui)
                    .foregroundStyle(exists ? Quiet.ink : Quiet.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(exists
                     ? capture.createdAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
                     : "Moved or deleted")
                    .font(Quiet.Font.caption)
                    .foregroundStyle(Quiet.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Quiet.Space.s2)
        .padding(.vertical, Quiet.Space.s2)
        .background(
            RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous)
                .fill(selected ? Quiet.selection : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
