import Foundation
import Testing
@testable import ClipboardKit

@Suite("Clip content")
struct ClipContentTests {

    @Test("Each content case reports its kind")
    func testKinds() {
        #expect(ClipContent.text("a").kind == .text)
        #expect(ClipContent.richText(rtf: Data("{\\rtf1 a}".utf8), plainText: "a").kind == .richText)
        #expect(ClipContent.image(data: samplePNG, typeIdentifier: "public.png").kind == .image)
        #expect(ClipContent.fileURLs([URL(fileURLWithPath: "/tmp/a.txt")]).kind == .fileURLs)
        #expect(ClipContent.colour(ClipColour(red: 1, green: 0, blue: 0)).kind == .colour)
    }

    @Test("The same content gives the same fingerprint")
    func testSameHash() {
        #expect(ClipContent.text("hello").contentHash == ClipContent.text("hello").contentHash)
        #expect(ClipContent.text("hello").contentHash.count == 64)
    }

    @Test("Different content, or the same bytes as a different kind, gives a different fingerprint")
    func testDifferentHash() {
        #expect(ClipContent.text("hello").contentHash != ClipContent.text("hello!").contentHash)
        let bytes = Data("hello".utf8)
        let asText = ClipContent.text("hello").contentHash
        let asRich = ClipContent.richText(rtf: bytes, plainText: "hello").contentHash
        let asImage = ClipContent.image(data: bytes, typeIdentifier: "public.png").contentHash
        #expect(Set([asText, asRich, asImage]).count == 3)
    }

    @Test("Size counts the stored bytes; rich text counts both forms")
    func testByteSize() {
        #expect(ClipContent.text("héllo").byteSize == 6)
        let rtf = Data(repeating: 1, count: 40)
        #expect(ClipContent.richText(rtf: rtf, plainText: "abc").byteSize == 43)
        #expect(ClipContent.image(data: samplePNG, typeIdentifier: "public.png").byteSize == samplePNG.count)
    }

    @Test("Previews are one line and cut at 200 characters")
    func testPreview() {
        #expect(ClipContent.text("  one\n\ttwo   three \n").preview == "one two three")
        let long = String(repeating: "x", count: 300)
        let preview = ClipContent.text(long).preview
        #expect(preview.count == ClipContent.previewLength + 1)
        #expect(preview.hasSuffix("…"))
        #expect(ClipContent.image(data: samplePNG, typeIdentifier: "public.png").preview.isEmpty)
    }

    @Test("File previews show file names")
    func testFilePreview() {
        let urls = [URL(fileURLWithPath: "/Users/x/report.pdf"), URL(fileURLWithPath: "/tmp/b.png")]
        #expect(ClipContent.fileURLs(urls).preview == "report.pdf, b.png")
    }

    @Test("Colours show as hex and are clamped")
    func testColour() {
        #expect(ClipColour(red: 1, green: 0.5, blue: 0).hexString == "#FF8000")
        #expect(ClipColour(red: 0, green: 0, blue: 0, alpha: 0.5).hexString == "#00000080")
        #expect(ClipColour(red: 2, green: -1, blue: 0.5) == ClipColour(red: 1, green: 0, blue: 0.5))
        let colour = ClipColour(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        #expect(ClipColour(storageString: colour.storageString) == colour)
        #expect(ClipColour(storageString: "nonsense") == nil)
    }

    @Test("A new item takes its fields from the content")
    func testNewItem() {
        let content = ClipContent.text("abc")
        let item = ClipItem(content: content, sourceApp: "com.apple.TextEdit", now: referenceDate)
        #expect(item.kind == .text)
        #expect(item.contentHash == content.contentHash)
        #expect(item.byteSize == 3)
        #expect(item.preview == "abc")
        #expect(item.createdAt == referenceDate)
        #expect(item.lastUsedAt == referenceDate)
        #expect(!item.pinned)
        #expect(item.sourceApp == "com.apple.TextEdit")
    }
}
