import Testing
import CoreGraphics
@testable import DocShot

@Suite("Preview Thumbnail Tests")
struct PreviewThumbnailTests {

    // MARK: - Keys

    @Test("Return and keypad Enter copy")
    func testReturnCopies() {
        for keyCode in [PreviewThumbnailKeyCommand.returnKeyCode, PreviewThumbnailKeyCommand.keypadEnterKeyCode] {
            #expect(PreviewThumbnailKeyCommand.resolve(
                characters: "\r", keyCode: keyCode, hasCommand: false, hasOtherModifiers: false
            ) == .copy)
        }
    }

    @Test("Escape discards")
    func testEscapeDiscards() {
        #expect(PreviewThumbnailKeyCommand.resolve(
            characters: "\u{1b}", keyCode: PreviewThumbnailKeyCommand.escapeKeyCode,
            hasCommand: false, hasOtherModifiers: false
        ) == .discard)
    }

    @Test("Cmd+C copies and Cmd+S saves, in either case")
    func testCommandKeys() {
        #expect(PreviewThumbnailKeyCommand.resolve(characters: "c", keyCode: 8, hasCommand: true, hasOtherModifiers: false) == .copy)
        #expect(PreviewThumbnailKeyCommand.resolve(characters: "C", keyCode: 8, hasCommand: true, hasOtherModifiers: false) == .copy)
        #expect(PreviewThumbnailKeyCommand.resolve(characters: "s", keyCode: 1, hasCommand: true, hasOtherModifiers: false) == .save)
    }

    @Test("Plain letters, other chords and modified Return do nothing")
    func testUnhandledKeys() {
        // Plain C and S are not shortcuts on the thumbnail.
        #expect(PreviewThumbnailKeyCommand.resolve(characters: "c", keyCode: 8, hasCommand: false, hasOtherModifiers: false) == nil)
        #expect(PreviewThumbnailKeyCommand.resolve(characters: "s", keyCode: 1, hasCommand: false, hasOtherModifiers: false) == nil)
        // Shift+Cmd+S and Option+Return belong to someone else.
        #expect(PreviewThumbnailKeyCommand.resolve(characters: "s", keyCode: 1, hasCommand: true, hasOtherModifiers: true) == nil)
        #expect(PreviewThumbnailKeyCommand.resolve(
            characters: "\r", keyCode: PreviewThumbnailKeyCommand.returnKeyCode, hasCommand: false, hasOtherModifiers: true
        ) == nil)
        // Cmd+Return and Cmd+Escape are not thumbnail shortcuts.
        #expect(PreviewThumbnailKeyCommand.resolve(
            characters: "\r", keyCode: PreviewThumbnailKeyCommand.returnKeyCode, hasCommand: true, hasOtherModifiers: false
        ) == nil)
        #expect(PreviewThumbnailKeyCommand.resolve(characters: "v", keyCode: 9, hasCommand: true, hasOtherModifiers: false) == nil)
    }

    @Test("Buttons run left to right as Copy, Save, Edit, Discard")
    func testButtonOrder() {
        #expect(PreviewThumbnailAction.displayOrder == [.copy, .save, .edit, .discard])
        #expect(Set(PreviewThumbnailAction.displayOrder) == Set(PreviewThumbnailAction.allCases))
    }

    // MARK: - Layout

    @Test("A wide Retina capture is scaled into the box, keeping its aspect ratio")
    func testWideImageFits() {
        let size = PreviewThumbnailLayout.imageSize(forPixelSize: CGSize(width: 2880, height: 1800), backingScale: 2)
        #expect(size.width == 240)
        #expect(size.height == 150)
    }

    @Test("A tall capture is limited by height")
    func testTallImageFits() {
        let size = PreviewThumbnailLayout.imageSize(forPixelSize: CGSize(width: 600, height: 1800), backingScale: 2)
        #expect(size.height == 150)
        #expect(size.width == 50)
    }

    @Test("A small capture is never upscaled")
    func testSmallImageKeepsSize() {
        let size = PreviewThumbnailLayout.imageSize(forPixelSize: CGSize(width: 100, height: 60), backingScale: 2)
        #expect(size == CGSize(width: 50, height: 30))
    }

    @Test("A one-pixel capture still gets a visible size")
    func testTinyImage() {
        let size = PreviewThumbnailLayout.imageSize(forPixelSize: CGSize(width: 1, height: 1), backingScale: 2)
        #expect(size.width >= 1)
        #expect(size.height >= 1)
    }

    @Test("The panel sits in the bottom-right of the visible frame, inside it")
    func testPanelPlacement() {
        // A visible frame that starts above a bottom Dock and right of the display origin.
        let visible = CGRect(x: 1440, y: 80, width: 1920, height: 1000)
        let frame = PreviewThumbnailLayout.panelFrame(imageSize: CGSize(width: 240, height: 150), visibleFrame: visible)

        #expect(frame.maxX == visible.maxX - PreviewThumbnailLayout.screenMargin)
        #expect(frame.minY == visible.minY + PreviewThumbnailLayout.screenMargin)
        #expect(visible.contains(frame))
    }

    @Test("The panel is never narrower than the button row")
    func testPanelFitsButtons() {
        let frame = PreviewThumbnailLayout.panelFrame(
            imageSize: CGSize(width: 20, height: 150),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
        )
        #expect(frame.width >= PreviewThumbnailLayout.buttonRowWidth + PreviewThumbnailLayout.padding * 2)
    }
}
