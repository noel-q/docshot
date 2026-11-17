import Testing
import Foundation
@testable import DocShot

@Suite("Annotation Tool Key Map Tests")
struct AnnotationToolKeyTests {

    @Test("Each tool has its key from the plan",
          arguments: [
            ("V", AnnotationTool.select),
            ("A", .arrow),
            ("R", .rectangle),
            ("O", .ellipse),
            ("T", .text),
            ("H", .highlighter),
            ("X", .redaction),
            ("C", .crop)
          ])
    func testKeyMap(key: String, tool: AnnotationTool) {
        #expect(String(tool.shortcutKey) == key)
        #expect(AnnotationTool.tool(forKey: key) == tool)
        #expect(AnnotationTool.tool(forKey: key.lowercased()) == tool)
    }

    @Test("Every tool has a distinct key")
    func testKeysAreUnique() {
        let keys = AnnotationTool.allCases.map(\.shortcutKey)
        #expect(Set(keys).count == AnnotationTool.allCases.count)
    }

    @Test("Keys outside the map select nothing")
    func testUnmappedKeys() {
        #expect(AnnotationTool.tool(forKey: "Z") == nil)
        #expect(AnnotationTool.tool(forKey: "1") == nil)
        #expect(AnnotationTool.tool(forKey: "") == nil)
        #expect(AnnotationTool.tool(forKey: "VA") == nil)
    }

    @Test("Tooltips carry the key")
    func testTooltips() {
        #expect(AnnotationTool.select.tooltip == "Select / Move (V)")
        #expect(AnnotationTool.redaction.tooltip == "Redaction (X)")
        for tool in AnnotationTool.allCases {
            #expect(tool.tooltip.hasSuffix("(\(tool.shortcutKey))"))
        }
    }

    @Test("A plain tool key selects the tool")
    func testPlainKeySelectsTool() {
        let command = EditorKeyCommand.resolve(
            characters: "r", keyCode: 15, hasCommandModifiers: false, isEditingText: false
        )
        #expect(command == .selectTool(.rectangle))
    }

    @Test("Return and keypad Enter copy and close")
    func testReturnCopiesAndCloses() {
        for keyCode in [EditorKeyCommand.returnKeyCode, EditorKeyCommand.keypadEnterKeyCode] {
            let command = EditorKeyCommand.resolve(
                characters: "\r", keyCode: keyCode, hasCommandModifiers: false, isEditingText: false
            )
            #expect(command == .copyAndClose)
        }
    }

    @Test("Nothing fires while text is being edited")
    func testInactiveWhileEditingText() {
        #expect(EditorKeyCommand.resolve(
            characters: "c", keyCode: 8, hasCommandModifiers: false, isEditingText: true) == nil)
        #expect(EditorKeyCommand.resolve(
            characters: "\r", keyCode: EditorKeyCommand.returnKeyCode,
            hasCommandModifiers: false, isEditingText: true) == nil)
    }

    @Test("Command chords stay with the existing editor shortcuts")
    func testCommandChordsAreIgnored() {
        // Cmd+C is Copy, not Crop.
        #expect(EditorKeyCommand.resolve(
            characters: "c", keyCode: 8, hasCommandModifiers: true, isEditingText: false) == nil)
        #expect(EditorKeyCommand.resolve(
            characters: "\r", keyCode: EditorKeyCommand.returnKeyCode,
            hasCommandModifiers: true, isEditingText: false) == nil)
    }

    @Test("Unmapped keys pass through")
    func testUnmappedKeyPassesThrough() {
        #expect(EditorKeyCommand.resolve(
            characters: "z", keyCode: 6, hasCommandModifiers: false, isEditingText: false) == nil)
        #expect(EditorKeyCommand.resolve(
            characters: nil, keyCode: 6, hasCommandModifiers: false, isEditingText: false) == nil)
    }
}
