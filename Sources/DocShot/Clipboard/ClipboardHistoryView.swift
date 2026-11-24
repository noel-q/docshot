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

    static let listWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            if controller.isEnabled {
                topBar
                if controller.isPaused {
                    pausedLine
                }
                Rectangle().fill(Quiet.line).frame(height: 1)
                HStack(spacing: 0) {
                    list
                        .frame(width: Self.listWidth)
                    Rectangle().fill(Quiet.line).frame(width: 1)
                    ClipPreviewPane(item: model.selectedItem, controller: controller)
                }
                Rectangle().fill(Quiet.line).frame(height: 1)
                footer
            } else {
                offState
            }
        }
        .frame(minWidth: 600, minHeight: 360)
        .background(Quiet.canvas)
        // The title bar is merged into the content (restyle plan 6): the search bar sits at
        // the very top rather than below an empty title bar band.
        .ignoresSafeArea(.container, edges: .top)
        .tint(Quiet.accent)
        .onChange(of: model.focusRequest) { _, _ in searchFocused = true }
        .onAppear { searchFocused = true }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) { controller.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps: \(controller.clearKeep.title.lowercased()). This cannot be undone.")
        }
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
            Picker("Show", selection: $model.filter) {
                ForEach(ClipboardFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel("Show")
            Menu {
                Button(controller.isPaused ? "Resume history" : "Pause history") {
                    controller.setPaused(!controller.isPaused)
                }
                Button("Clear history…") { confirmingClear = true }
                    .disabled(controller.items.isEmpty)
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
                    ? "Text inside images is not searched yet."
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
                .frame(maxWidth: 420, alignment: .leading)
            HStack(spacing: Quiet.Space.s2) {
                // No Return shortcut: turning history on starts recording, so it takes a click.
                Button("Turn on") { controller.setEnabled(true) }
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
                hint("⌘C", "Copy")
                hint("⌘P", model.selectedItem?.pinned == true ? "Unpin" : "Pin")
                hint("⌘⌫", "Delete")
                if controller.pasteDirectly && !controller.pasteAllowed {
                    Text("Allow pasting in Settings")
                        .foregroundStyle(Quiet.inkMuted)
                        .lineLimit(1)
                }
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
            Text(label).foregroundStyle(Quiet.inkFaint)
        }
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
