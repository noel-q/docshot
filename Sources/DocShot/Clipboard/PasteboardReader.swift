import AppKit
import ClipboardKit
import ImageIO
import UniformTypeIdentifiers

/// Moves content between a pasteboard and `ClipContent` (plan section 4.3). Works on any
/// pasteboard, so tests use a private one and never touch the general pasteboard.
enum PasteboardReader {

    /// What the watcher knows about a change before reading any content.
    static func change(of pasteboard: NSPasteboard, frontmostBundleID: String?) -> ClipboardChange {
        ClipboardChange(
            changeCount: pasteboard.changeCount,
            types: pasteboard.types?.map(\.rawValue) ?? [],
            frontmostBundleID: frontmostBundleID
        )
    }

    /// The content history keeps, in order of preference: files, text (rich, then plain),
    /// image, colour. Text wins over an image because apps such as spreadsheets and word
    /// processors add a picture of copied text; the exception is text that is only a link, which
    /// browsers add beside a copied image. Nil when nothing usable is present. A TIFF-only image
    /// is returned as TIFF; call `normalized(_:)` off the main thread to convert it.
    static func content(from pasteboard: NSPasteboard) -> ClipContent? {
        let types = pasteboard.types ?? []

        if types.contains(.fileURL),
           let urls = pasteboard.readObjects(
               forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
           ) as? [URL], !urls.isEmpty {
            return .fileURLs(urls)
        }

        let hasImage = types.contains(.png) || types.contains(.tiff)
        let plain = types.contains(.string) ? pasteboard.string(forType: .string) : nil
        // Beside an image, text wins only if it says something: not a lone link, and not empty,
        // whitespace or the attachment placeholder rich-text editors put for an inline picture.
        let textYieldsToImage = hasImage && (plain.map { isLinkOnly($0) || !hasWords($0) } ?? true)
        if !textYieldsToImage {
            if types.contains(.rtf), let rtf = pasteboard.data(forType: .rtf) {
                let text = plain ?? NSAttributedString(rtf: rtf, documentAttributes: nil)?.string ?? ""
                return .richText(rtf: rtf, plainText: text)
            }
            if let plain {
                return .text(plain)
            }
        }

        if types.contains(.png), let data = pasteboard.data(forType: .png) {
            return .image(data: data, typeIdentifier: UTType.png.identifier)
        }
        if types.contains(.tiff), let data = pasteboard.data(forType: .tiff) {
            return .image(data: data, typeIdentifier: UTType.tiff.identifier)
        }
        if let plain {
            return .text(plain)
        }
        if types.contains(.color), let colour = NSColor(from: pasteboard),
           let srgb = colour.usingColorSpace(.sRGB) {
            return .colour(ClipColour(
                red: Double(srgb.redComponent), green: Double(srgb.greenComponent),
                blue: Double(srgb.blueComponent), alpha: Double(srgb.alphaComponent)
            ))
        }
        return nil
    }

    /// Converts a TIFF image to PNG (decided 23 November 2026: TIFF is often many times larger).
    /// Everything else, and a TIFF that cannot be converted, is returned unchanged.
    static func normalized(_ content: ClipContent) -> ClipContent {
        guard case .image(let data, let type) = content, type == UTType.tiff.identifier,
              let png = pngData(fromImageData: data) else {
            return content
        }
        return .image(data: png, typeIdentifier: UTType.png.identifier)
    }

    /// True when the text has something besides whitespace and attachment placeholders (U+FFFC).
    static func hasWords(_ string: String) -> Bool {
        string.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "\u{FFFC}" }
    }

    /// One web or file link and nothing else, as browsers put beside a copied image.
    static func isLinkOnly(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "file"].contains(scheme)
    }

    static func pngData(fromImageData data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        // Keep the image properties, so a Retina image keeps its resolution and pastes at its size.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Puts content on the pasteboard and returns the resulting change count, which the watcher
    /// then ignores as DocShot's own write.
    @discardableResult
    static func write(_ content: ClipContent, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        switch content {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .richText(let rtf, let plainText):
            pasteboard.setData(rtf, forType: .rtf)
            pasteboard.setString(plainText, forType: .string)
        case .image(let data, let type):
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
        case .fileURLs(let urls):
            pasteboard.writeObjects(urls as [NSURL])
        case .colour(let colour):
            // NSColor writes only to a pasteboard that has declared the colour type.
            pasteboard.declareTypes([.color], owner: nil)
            NSColor(srgbRed: colour.red, green: colour.green, blue: colour.blue, alpha: colour.alpha)
                .write(to: pasteboard)
        }
        return pasteboard.changeCount
    }
}
