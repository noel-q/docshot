import Foundation

public enum AnnotationTool: String, CaseIterable, Identifiable, Sendable {
    case select = "Select / Move"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case text = "Text"
    case highlighter = "Highlighter"
    case redaction = "Redaction"
    case crop = "Crop"
    
    public var id: String { rawValue }
    
    public var systemImage: String {
        switch self {
        case .select: return "arrow.triangle.2.circlepath"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "square"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .highlighter: return "pencil.tip"
        case .redaction: return "eye.slash"
        case .crop: return "crop"
        }
    }

    /// The single key that selects this tool while the editor canvas has focus.
    public var shortcutKey: Character {
        switch self {
        case .select: return "V"
        case .arrow: return "A"
        case .rectangle: return "R"
        case .ellipse: return "O"
        case .text: return "T"
        case .highlighter: return "H"
        case .redaction: return "X"
        case .crop: return "C"
        }
    }

    /// Toolbar tooltip: the tool name with its key.
    public var tooltip: String { "\(rawValue) (\(shortcutKey))" }

    /// The tool for a typed key, ignoring case. Nil for anything that is not one tool key.
    public static func tool(forKey characters: String) -> AnnotationTool? {
        let key = characters.uppercased()
        guard key.count == 1 else { return nil }
        return allCases.first { String($0.shortcutKey) == key }
    }
}

/// What a plain key press means in the image editor. Pure, so the key map and its guard
/// conditions can be tested without a window.
public enum EditorKeyCommand: Equatable, Sendable {
    case selectTool(AnnotationTool)
    case copyAndClose

    public static let returnKeyCode: UInt16 = 36
    public static let keypadEnterKeyCode: UInt16 = 76

    /// - Parameters:
    ///   - hasCommandModifiers: Command, Option or Control is held. Those chords belong to
    ///     the existing editor shortcuts (Cmd+C, Cmd+S, Cmd+Z), never to tool keys.
    ///   - isEditingText: a text field owns the keyboard, so every key is typing.
    public static func resolve(
        characters: String?,
        keyCode: UInt16,
        hasCommandModifiers: Bool,
        isEditingText: Bool
    ) -> EditorKeyCommand? {
        guard !hasCommandModifiers, !isEditingText else { return nil }
        if keyCode == returnKeyCode || keyCode == keypadEnterKeyCode {
            return .copyAndClose
        }
        guard let characters, let tool = AnnotationTool.tool(forKey: characters) else { return nil }
        return .selectTool(tool)
    }
}
