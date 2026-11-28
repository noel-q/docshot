import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
import ClipboardKit
@testable import DocShot

/// Every test uses a private, uniquely named pasteboard (testing rule 1), never the general one.
@Suite("Pasteboard reader")
@MainActor
struct PasteboardReaderTests {

    static func privatePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("DocShotTests.\(UUID().uuidString)"))
    }

    /// A small real image, encoded as `type`.
    static func imageData(_ type: UTType, side: Int = 32) -> Data {
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = context.makeImage()!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47])

    @Test("Text, rich text, files and colours read back as written", arguments: [
        ClipContent.text("hello ✓\nworld"),
        .richText(rtf: Data("{\\rtf1\\ansi bold}".utf8), plainText: "bold"),
        .fileURLs([URL(fileURLWithPath: "/tmp/a file.txt"), URL(fileURLWithPath: "/tmp/b.pdf")]),
        .colour(ClipColour(red: 1, green: 0, blue: 0)),
    ])
    func testRoundTrip(content: ClipContent) throws {
        let pasteboard = Self.privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        PasteboardReader.write(content, to: pasteboard)
        let read = try #require(PasteboardReader.content(from: pasteboard))
        if case .colour(let colour) = read, case .colour(let expected) = content {
            #expect(abs(colour.red - expected.red) < 0.01)
            #expect(abs(colour.green - expected.green) < 0.01)
            #expect(abs(colour.blue - expected.blue) < 0.01)
        } else {
            #expect(read == content)
        }
    }

    @Test("PNG is preferred when an image is offered as PNG and TIFF")
    func testPrefersPNG() throws {
        let pasteboard = Self.privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let png = Self.imageData(.png)
        pasteboard.setData(Self.imageData(.tiff), forType: .tiff)
        pasteboard.setData(png, forType: .png)
        #expect(PasteboardReader.content(from: pasteboard) == .image(data: png, typeIdentifier: "public.png"))
    }

    @Test("A TIFF-only image is converted to PNG")
    func testTIFFConverted() throws {
        let pasteboard = Self.privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setData(Self.imageData(.tiff, side: 200), forType: .tiff)

        let read = try #require(PasteboardReader.content(from: pasteboard))
        guard case .image(let tiff, let type) = read else {
            Issue.record("expected an image, got \(read)")
            return
        }
        #expect(type == "public.tiff")

        guard case .image(let png, let newType) = PasteboardReader.normalized(read) else {
            Issue.record("expected an image after conversion")
            return
        }
        #expect(newType == "public.png")
        #expect(png.prefix(4) == Self.pngSignature)
        #expect(png.count < tiff.count)
    }

    @Test("Conversion leaves other content and unreadable TIFF data unchanged")
    func testNormalizeLeavesOthers() {
        let text = ClipContent.text("x")
        #expect(PasteboardReader.normalized(text) == text)
        let png = ClipContent.image(data: Self.imageData(.png), typeIdentifier: "public.png")
        #expect(PasteboardReader.normalized(png) == png)
        let broken = ClipContent.image(data: Data([1, 2, 3]), typeIdentifier: "public.tiff")
        #expect(PasteboardReader.normalized(broken) == broken)
    }

    @Test("Text wins over a picture of it, as spreadsheets and word processors copy")
    func testTextBeforeImage() throws {
        let pasteboard = Self.privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setData(Self.imageData(.png), forType: .png)
        pasteboard.setString("A1\tB1\n2\t3", forType: .string)
        #expect(PasteboardReader.content(from: pasteboard) == .text("A1\tB1\n2\t3"))

        pasteboard.clearContents()
        let rtf = Data("{\\rtf1\\ansi Cell}".utf8)
        pasteboard.setData(Self.imageData(.tiff), forType: .tiff)
        pasteboard.setData(rtf, forType: .rtf)
        pasteboard.setString("Cell", forType: .string)
        #expect(PasteboardReader.content(from: pasteboard) == .richText(rtf: rtf, plainText: "Cell"))
    }

    @Test("An image wins over a lone link, as browsers copy an image")
    func testImageBeforeLink() throws {
        let pasteboard = Self.privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let png = Self.imageData(.png)
        pasteboard.setData(png, forType: .png)
        pasteboard.setString("https://example.com/picture.png", forType: .string)
        #expect(PasteboardReader.content(from: pasteboard) == .image(data: png, typeIdentifier: "public.png"))
    }

    @Test("An image wins over empty text or the placeholder of an inline picture",
          arguments: ["", "  \n", "\u{FFFC}", " \u{FFFC}\n"])
    func testImageBeforeEmptyText(text: String) throws {
        let pasteboard = Self.privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let png = Self.imageData(.png)
        pasteboard.setData(png, forType: .png)
        pasteboard.setData(Data("{\\rtf1\\ansi x}".utf8), forType: .rtf)
        pasteboard.setString(text, forType: .string)
        #expect(PasteboardReader.content(from: pasteboard) == .image(data: png, typeIdentifier: "public.png"))
    }

    @Test("Text with words still wins over an image even beside a placeholder")
    func testWordsBeatImage() {
        #expect(PasteboardReader.hasWords("Caption \u{FFFC}"))
        #expect(!PasteboardReader.hasWords("\u{FFFC} \n"))
    }

    @Test("Only a single web or file link counts as a link")
    func testLinkOnly() {
        #expect(PasteboardReader.isLinkOnly("https://example.com/a.png"))
        #expect(PasteboardReader.isLinkOnly("  http://example.com \n"))
        #expect(PasteboardReader.isLinkOnly("file:///tmp/a.png"))
        #expect(!PasteboardReader.isLinkOnly("see https://example.com"))
        #expect(!PasteboardReader.isLinkOnly("mailto:a@example.com"))
        #expect(!PasteboardReader.isLinkOnly("plain words"))
        #expect(!PasteboardReader.isLinkOnly(""))
    }

    @Test("Converting TIFF to PNG keeps the resolution, so Retina images paste at their size")
    func testConversionKeepsDPI() throws {
        let context = CGContext(
            data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.tiff.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [
            kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144,
        ] as CFDictionary)
        CGImageDestinationFinalize(destination)

        let png = try #require(PasteboardReader.pngData(fromImageData: output as Data))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue == 144)
    }

    @Test("Files win over the file name text Finder also puts on the clipboard")
    func testFilesFirst() throws {
        let pasteboard = Self.privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let url = URL(fileURLWithPath: "/tmp/report.pdf")
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString("report.pdf", forType: .string)
        #expect(PasteboardReader.content(from: pasteboard) == .fileURLs([url]))
    }

    @Test("Rich text keeps its plain text for search and plain pasting")
    func testRichTextPlain() throws {
        let pasteboard = Self.privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let rtf = Data("{\\rtf1\\ansi Hello}".utf8)
        pasteboard.setData(rtf, forType: .rtf)
        #expect(PasteboardReader.content(from: pasteboard) == .richText(rtf: rtf, plainText: "Hello"))
    }

    @Test("An empty pasteboard or an unknown type gives no content")
    func testNothing() {
        let pasteboard = Self.privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(PasteboardReader.content(from: pasteboard) == nil)
        pasteboard.setData(Data([1]), forType: NSPasteboard.PasteboardType("com.example.private"))
        #expect(PasteboardReader.content(from: pasteboard) == nil)
    }

    @Test("A write returns the change count the watcher will see")
    func testWriteChangeCount() {
        let pasteboard = Self.privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        let before = pasteboard.changeCount
        let count = PasteboardReader.write(.text("mine"), to: pasteboard)
        #expect(count > before)
        #expect(count == pasteboard.changeCount)
    }

    @Test("The change lists the types, the count and the front app")
    func testChange() {
        let pasteboard = Self.privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("secret", forType: .string)
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let change = PasteboardReader.change(of: pasteboard, frontmostBundleID: "com.example.app")
        #expect(change.changeCount == pasteboard.changeCount)
        #expect(change.types.contains("org.nspasteboard.ConcealedType"))
        #expect(change.frontmostBundleID == "com.example.app")
        #expect(RecordingRules().decide(change, historyEnabled: true, paused: false, ownWriteChangeCounts: [])
                == .skip(.marker("org.nspasteboard.ConcealedType")))
    }
}
