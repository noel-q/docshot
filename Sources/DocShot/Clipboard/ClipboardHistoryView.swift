import AppKit
import ClipboardKit
import ImageIO
import SwiftUI

/// The Clipboard section of the DocShot window (plan section 3; C3: search, keys, pins).
/// Plain on purpose: it is restyled later as the pilot for Noel's design system (C3 plan, 8).
struct ClipboardHistoryView: View {
    /// Redraws this view when the colour theme changes (C0.7).
    @ObservedObject var themeController = ThemeController.shared
    @ObservedObject var model: ClipboardWindowModel
    @ObservedObject var controller: ClipboardHistoryController
    let onChoose: (ClipItem) -> Void

    @State private var confirmingClear = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if controller.isEnabled {
                Divider()
                footer
            }
        }
        .frame(minWidth: 340, minHeight: 360)
        .background(DesignTokens.windowBackground)
        .onChange(of: model.focusRequest) { _, _ in searchFocused = true }
        .onAppear { searchFocused = true }
        .confirmationDialog(
            "Clear clipboard history?",
            isPresented: $confirmingClear
        ) {
            Button("Clear", role: .destructive) { controller.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps: \(controller.clearKeep.title.lowercased()). This cannot be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if controller.isEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DesignTokens.secondaryText)
                    TextField("Search", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($searchFocused)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(DesignTokens.cardBackground))
                if controller.isPaused {
                    Text("Paused")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DesignTokens.cardBackground))
                        .overlay(Capsule().stroke(DesignTokens.borderAdaptive, lineWidth: 1))
                }
                Button(controller.isPaused ? "Resume" : "Pause") {
                    controller.setPaused(!controller.isPaused)
                }
                .help(controller.isPaused ? "Start recording copies again" : "Stop recording copies until resumed")
                Button("Clear…") { confirmingClear = true }
                    .disabled(controller.items.isEmpty)
                    .help("Clear history. Keeps: \(controller.clearKeep.title.lowercased())")
            } else {
                Text("Clipboard")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if !controller.isEnabled {
            message(
                title: "Clipboard history is off",
                detail: "When it is on, DocShot keeps what you copy on this Mac only. Copies from password managers are skipped.",
                action: ("Turn On", { controller.setEnabled(true) })
            )
        } else if controller.items.isEmpty {
            message(
                title: controller.isPaused ? "History is paused" : "Nothing copied yet",
                detail: controller.isPaused
                    ? "Copies are not recorded until you resume."
                    : "Copy something in any app and it appears here.",
                action: nil
            )
        } else if model.rows.isEmpty && model.isSearching {
            message(title: "No matches", detail: "Text inside images is not searched yet.", action: nil)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if !model.pinned.isEmpty {
                            sectionTitle("Pinned")
                            rows(model.pinned)
                            if !model.others.isEmpty {
                                sectionTitle("Recent")
                            }
                        }
                        rows(model.others)
                    }
                    .padding(8)
                }
                .onChange(of: model.selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func rows(_ items: [ClipItem]) -> some View {
        ForEach(items) { item in
            ClipRowView(
                item: item,
                controller: controller,
                selected: item.id == model.selectedID,
                onChoose: {
                    model.select(item.id)
                    onChoose(item)
                }
            )
            .id(item.id)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(DesignTokens.secondaryText)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let problem = controller.problem {
                Text(problem).foregroundColor(.red)
            } else if let notice = controller.notice {
                Text(notice).foregroundColor(.orange)
            } else {
                Text(hint).foregroundColor(DesignTokens.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .lineLimit(2)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var hint: String {
        let first = controller.pasteDirectly && controller.pasteAllowed ? "Return pastes" : "Return copies"
        var parts = [first, "⌘C copies", "⌘P pins", "⌘⌫ deletes"]
        if controller.pasteDirectly && !controller.pasteAllowed {
            parts.append("allow pasting in Settings")
        }
        return parts.joined(separator: " · ")
    }

    private func message(title: String, detail: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(DesignTokens.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.primaryAccent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

/// One history row. A click pastes (C3 plan, decision 1); pin and delete show under the pointer.
private struct ClipRowView: View {
    @ObservedObject var themeController = ThemeController.shared
    let item: ClipItem
    let controller: ClipboardHistoryController
    let selected: Bool
    let onChoose: () -> Void

    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onChoose) {
                HStack(spacing: 10) {
                    leading
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 12))
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(DesignTokens.secondaryText)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.pinned ? "Pinned " : "")\(kindName): \(title)")
            .accessibilityHint("Pastes this item into the app you were in")

            if hovering {
                rowButton(item.pinned ? "pin.slash" : "pin", help: item.pinned ? "Unpin (⌘P)" : "Pin (⌘P)") {
                    controller.togglePin(item)
                }
                rowButton("trash", help: "Delete (⌘⌫)") {
                    controller.delete(item)
                }
            } else if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(DesignTokens.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? DesignTokens.primaryAccent.opacity(0.18)
                      : hovering ? DesignTokens.cardBackground : Color.clear)
        )
        .onHover { hovering = $0 }
        .task(id: item.id) {
            guard item.kind == .image, thumbnail == nil,
                  let url = await controller.imageFileURL(for: item) else { return }
            thumbnail = await ThumbnailLoader.thumbnail(for: url, maxPixelSize: 120)
        }
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(DesignTokens.secondaryText)
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder
    private var leading: some View {
        if item.kind == .image, let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if item.kind == .colour {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: item.preview) ?? .gray)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.borderAdaptive, lineWidth: 1))
        } else {
            Image(systemName: symbolName)
                .font(.system(size: 16))
                .foregroundColor(DesignTokens.secondaryText)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 6).fill(DesignTokens.cardBackground))
        }
    }

    private var title: String {
        switch item.kind {
        case .image: return "Image"
        default: return item.preview.isEmpty ? "(empty)" : item.preview
        }
    }

    private var kindName: String {
        switch item.kind {
        case .text: return "Text"
        case .richText: return "Formatted text"
        case .image: return "Image"
        case .fileURLs: return "Files"
        case .colour: return "Colour"
        }
    }

    private var symbolName: String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .image: return "photo"
        case .fileURLs: return "doc"
        case .colour: return "paintpalette"
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let app = item.sourceApp.flatMap(Self.appName(for:)) {
            parts.append(app)
        }
        parts.append(Self.relativeFormatter.localizedString(for: item.lastUsedAt, relativeTo: Date()))
        if item.kind == .image {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static func appName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// Downsampled thumbnails, decoded off the main thread and cached for the session.
@MainActor
enum ThumbnailLoader {
    private static let cache = NSCache<NSURL, NSImage>()

    static func thumbnail(for url: URL, maxPixelSize: Int) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
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
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

private extension Color {
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
