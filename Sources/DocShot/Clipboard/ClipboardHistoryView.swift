import AppKit
import ClipboardKit
import ImageIO
import SwiftUI

/// The Clipboard section of the DocShot window (plan section 3, C2: read-only history).
struct ClipboardHistoryView: View {
    /// Redraws this view when the colour theme changes (C0.7).
    @ObservedObject var themeController = ThemeController.shared
    @ObservedObject var controller: ClipboardHistoryController
    let onCopied: () -> Void

    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 340, minHeight: 360)
        .background(DesignTokens.windowBackground)
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
            Text("Clipboard")
                .font(.system(size: 15, weight: .semibold))
            if controller.isEnabled && controller.isPaused {
                Text("Paused")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(DesignTokens.cardBackground))
                    .overlay(Capsule().stroke(DesignTokens.borderAdaptive, lineWidth: 1))
            }
            Spacer()
            if controller.isEnabled {
                Button(controller.isPaused ? "Resume" : "Pause") {
                    controller.setPaused(!controller.isPaused)
                }
                .help(controller.isPaused ? "Start recording copies again" : "Stop recording copies until resumed")
                Button("Clear…") { confirmingClear = true }
                    .disabled(controller.items.isEmpty)
                    .help("Clear history. Keeps: \(controller.clearKeep.title.lowercased())")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if !controller.isEnabled {
            message(
                title: "Clipboard history is off",
                detail: "When it is on, DocShot keeps what you copy on this Mac only: up to 200 items for 30 days. Copies from password managers are skipped.",
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
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(controller.items) { item in
                        ClipRowView(item: item, controller: controller) {
                            Task {
                                if await controller.copyBack(item) {
                                    onCopied()
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
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

/// One history row. Clicking it copies the item back (C2 plan, decision 1).
private struct ClipRowView: View {
    @ObservedObject var themeController = ThemeController.shared
    let item: ClipItem
    let controller: ClipboardHistoryController
    let onCopy: () -> Void

    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        Button(action: onCopy) {
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
            .padding(8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering ? DesignTokens.cardBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copy to the clipboard")
        .accessibilityLabel("\(kindName): \(title)")
        .accessibilityHint("Copies this item to the clipboard and closes the window")
        .task(id: item.id) {
            guard item.kind == .image, thumbnail == nil,
                  let url = await controller.imageFileURL(for: item) else { return }
            thumbnail = await ThumbnailLoader.thumbnail(for: url, maxPixelSize: 120)
        }
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
