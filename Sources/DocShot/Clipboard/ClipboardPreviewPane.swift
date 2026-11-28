import AppKit
import ClipboardKit
import ImageIO
import SwiftUI

/// Names, symbols and the "Source · time" line shared by rows and the preview pane.
@MainActor
enum ClipDescription {
    static func kindName(_ kind: ClipKind) -> String {
        switch kind {
        case .text: return "Text"
        case .richText: return "Formatted text"
        case .image: return "Image"
        case .fileURLs: return "Files"
        case .colour: return "Colour"
        }
    }

    static func symbol(for item: ClipItem) -> String {
        switch item.kind {
        case .text:
            if ClipPreviewText.linkHost(item.preview) != nil { return "link" }
            return ClipPreviewText.isCodeSource(item.sourceApp) ? "chevron.left.forwardslash.chevron.right" : "text.alignleft"
        case .richText: return "textformat"
        case .image: return "photo"
        case .fileURLs: return "doc"
        case .colour: return "paintpalette"
        }
    }

    static func appName(_ bundleID: String?) -> String? {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func metadata(for item: ClipItem) -> String {
        [appName(item.sourceApp), relative(item.lastUsedAt)].compactMap { $0 }.joined(separator: " · ")
    }

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

/// The preview side of the window (Quiet `ClipboardWindow`): a stage on `canvas` showing the
/// item itself, then Source, Copied, Type and Size. Cross-fades and rises 4 points when the
/// selection changes; a plain fade under Reduce Motion.
struct ClipPreviewPane: View {
    @ObservedObject var themeController = ThemeController.shared
    let item: ClipItem?
    let controller: ClipboardHistoryController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let item {
                ClipPreviewContent(item: item, controller: controller)
                    .id(item.id)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
            }
        }
        .animation(reduceMotion ? Quiet.Motion.fade : Quiet.Motion.fast, value: item?.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Quiet.surface)
    }
}

/// What the stage shows, worked out once per item off the main thread, so a very long text
/// item never stalls selection.
private enum PreparedPreview: Sendable {
    case text(shown: String, isCode: Bool)
    case link(host: String, address: String)
    case colour(ClipColour)
    case image
    case files([URL])
    case unreadable

    /// Text past this many characters is not shown; the whole item is still pasted.
    static let textLimit = 4_000

    static func prepare(_ content: ClipContent?, sourceApp: String?) -> (PreparedPreview, size: String?) {
        switch content {
        case .text(let text), .richText(_, let text):
            let size = ClipPreviewText.count(text.count, "character")
            // Only short text can be a lone link; never trim a huge string to find out.
            if text.utf8.count < 2_048, let host = ClipPreviewText.linkHost(text) {
                return (.link(host: host, address: text.trimmingCharacters(in: .whitespacesAndNewlines)), size)
            }
            let shown = text.count > textLimit ? String(text.prefix(textLimit)) + "…" : text
            return (.text(shown: shown, isCode: ClipPreviewText.isCodeSource(sourceApp)), size)
        case .colour(let colour):
            return (.colour(colour), ClipPreviewText.size(of: .colour(colour), pixelSize: nil, byteSize: 0))
        case .fileURLs(let urls):
            return (.files(urls), ClipPreviewText.count(urls.count, "file"))
        case .image:
            return (.image, nil)
        case nil:
            return (.unreadable, nil)
        }
    }
}

private struct ClipPreviewContent: View {
    let item: ClipItem
    let controller: ClipboardHistoryController

    @State private var prepared: PreparedPreview?
    @State private var sizeText: String?
    @State private var image: NSImage?
    /// Text found in an image (C4a): nil until read.
    @State private var recognised: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Quiet.Space.s4) {
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Quiet.Radius.md, style: .continuous).fill(Quiet.canvas)
                )
                .clipShape(RoundedRectangle(cornerRadius: Quiet.Radius.md, style: .continuous))
            if item.kind == .image, let recognised, !recognised.isEmpty {
                imageText(recognised)
            }
            details
        }
        .padding(Quiet.Space.s4)
        .task(id: item.id) { await load() }
    }

    // MARK: Stage

    @ViewBuilder
    private var stage: some View {
        switch prepared {
        case .text(let shown, let isCode):
            ScrollView {
                Text(shown)
                    .font(isCode ? Quiet.Font.codeLarge : Quiet.Font.headline.weight(.regular))
                    .foregroundStyle(Quiet.ink)
                    .lineSpacing(Quiet.Space.s1)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Quiet.Space.s6)
            }
        case .link(let host, let address):
            VStack(alignment: .leading, spacing: Quiet.Space.s2) {
                Image(systemName: "link")
                    .font(.system(size: 20))
                    .foregroundStyle(Quiet.inkMuted)
                Text(host)
                    .font(Quiet.Font.headline)
                    .foregroundStyle(Quiet.ink)
                Text(address)
                    .font(Quiet.Font.code)
                    .foregroundStyle(Quiet.inkMuted)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Quiet.Space.s6)
        case .colour(let colour):
            colourStage(colour)
        case .image:
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(Quiet.Space.s4)
                    .accessibilityLabel("Image preview")
            }
        case .files(let urls):
            filesStage(urls)
        case .unreadable:
            Text("This item could not be read.")
                .font(Quiet.Font.nativeBody)
                .foregroundStyle(Quiet.inkMuted)
        case nil:
            EmptyView()
        }
    }

    private func colourStage(_ colour: ClipColour) -> some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color(.sRGB, red: colour.red, green: colour.green, blue: colour.blue, opacity: colour.alpha))
            HStack(spacing: Quiet.Space.s2) {
                ForEach([colour.hexString, ClipPreviewText.rgb(colour), ClipPreviewText.hsl(colour)], id: \.self) { value in
                    Text(value)
                        .font(Quiet.Font.code)
                        .foregroundStyle(Quiet.ink)
                        .padding(.horizontal, Quiet.Space.s2)
                        .padding(.vertical, Quiet.Space.s1)
                        .background(
                            RoundedRectangle(cornerRadius: Quiet.Radius.xs, style: .continuous).fill(Quiet.surface)
                        )
                        .textSelection(.enabled)
                }
            }
            .padding(Quiet.Space.s3)
        }
    }

    private func filesStage(_ urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: Quiet.Space.s3) {
            ForEach(urls.prefix(6), id: \.self) { url in
                HStack(spacing: Quiet.Space.s3) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(url.lastPathComponent)
                            .font(Quiet.Font.ui)
                            .foregroundStyle(Quiet.ink)
                            .lineLimit(1)
                        Text(url.deletingLastPathComponent().path)
                            .font(Quiet.Font.caption)
                            .foregroundStyle(Quiet.inkMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            if urls.count > 6 {
                Text("and \(ClipPreviewText.count(urls.count - 6, "more file"))")
                    .font(Quiet.Font.caption)
                    .foregroundStyle(Quiet.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Quiet.Space.s6)
    }

    // MARK: Details

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: Quiet.Space.s4, verticalSpacing: Quiet.Space.s1) {
            row("Source", ClipDescription.appName(item.sourceApp) ?? "Unknown app")
            row("Copied", ClipDescription.relative(item.createdAt))
            row("Type", ClipDescription.kindName(item.kind))
            if let sizeText {
                row("Size", sizeText)
            }
        }
        .font(Quiet.Font.caption.monospacedDigit())
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Quiet.inkFaint)
                .frame(width: 72, alignment: .leading)
            Text(value).foregroundStyle(Quiet.ink).lineLimit(1)
        }
    }

    /// The text found in an image, a few lines of it, with Copy text and its key (C4a).
    private func imageText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Quiet.Space.s2) {
            HStack {
                Text("Text in this image")
                    .font(Quiet.Font.label)
                    .foregroundStyle(Quiet.inkMuted)
                Spacer(minLength: 0)
                Button {
                    controller.copyRecognisedText(text)
                } label: {
                    HStack(spacing: Quiet.Space.s1) {
                        KeyHint(keys: "⇧⌘C")
                        Text("Copy text").font(Quiet.Font.caption).foregroundStyle(Quiet.inkMuted)
                    }
                }
                .buttonStyle(.plain)
                .help("Copy the text in this image (⇧⌘C)")
                .accessibilityLabel("Copy text")
            }
            Text(text)
                .font(Quiet.Font.caption)
                .foregroundStyle(Quiet.ink)
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Loading

    private func load() async {
        if item.kind == .image {
            // Images need only their file: the thumbnail and its pixel size.
            prepared = .image
            recognised = await controller.recognisedText(for: item)
            let bytes = ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file)
            sizeText = bytes
            guard let url = await controller.imageFileURL(for: item) else { return }
            image = await ThumbnailLoader.thumbnail(for: url, maxPixelSize: 1200)
            if let pixels = await Task.detached(priority: .userInitiated, operation: { Self.pixelSize(of: url) }).value {
                sizeText = "\(Int(pixels.width)) × \(Int(pixels.height)) pixels, \(bytes)"
            }
            return
        }
        let content = await controller.previewContent(for: item)
        let sourceApp = item.sourceApp
        let result = await Task.detached(priority: .userInitiated) {
            PreparedPreview.prepare(content, sourceApp: sourceApp)
        }.value
        prepared = result.0
        sizeText = result.size
    }

    nonisolated private static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }
}
