import CoreGraphics

/// The four ways a screenshot can leave the preview thumbnail (plan section 7, C0.6).
/// Only `edit` opens the full editor; the other three finish the capture from the thumbnail.
public enum PreviewThumbnailAction: Equatable, Sendable, CaseIterable {
    case copy
    case save
    case edit
    case discard

    public var title: String {
        switch self {
        case .copy: return "Copy"
        case .save: return "Save"
        case .edit: return "Edit"
        case .discard: return "Discard"
        }
    }

    /// The key shown on the button and in its tooltip, matching `PreviewThumbnailKeyCommand`
    /// (Quiet: every action shows its key where it lives).
    public var keyHint: String {
        switch self {
        case .copy: return "↵"
        case .save: return "⌘S"
        case .edit: return "⌘E"
        case .discard: return "esc"
        }
    }

    public var symbolName: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .save: return "square.and.arrow.down"
        case .edit: return "pencil"
        case .discard: return "xmark"
        }
    }

    /// Button order, left to right.
    public static let displayOrder: [PreviewThumbnailAction] = [.copy, .save, .edit, .discard]
}

/// Keys the thumbnail answers while it has keyboard focus. Return and Cmd+C copy and close,
/// Cmd+S saves, Cmd+E opens the editor (Quiet restyle, 24 November 2026), Escape discards.
/// Anything else is passed on untouched.
public enum PreviewThumbnailKeyCommand {
    public static let returnKeyCode: UInt16 = 36
    public static let keypadEnterKeyCode: UInt16 = 76
    public static let escapeKeyCode: UInt16 = 53

    /// - Parameters:
    ///   - hasCommand: Command is held.
    ///   - hasOtherModifiers: Option, Control or Shift is held. Any of these turns the key into
    ///     something the thumbnail does not handle, so a chord such as Shift+Cmd+S is passed on.
    public static func resolve(
        characters: String?,
        keyCode: UInt16,
        hasCommand: Bool,
        hasOtherModifiers: Bool
    ) -> PreviewThumbnailAction? {
        guard !hasOtherModifiers else { return nil }

        if !hasCommand {
            switch keyCode {
            case returnKeyCode, keypadEnterKeyCode: return .copy
            case escapeKeyCode: return .discard
            default: return nil
            }
        }

        switch characters?.lowercased() {
        case "c": return .copy
        case "s": return .save
        case "e": return .edit
        default: return nil
        }
    }
}

/// Where the thumbnail panel sits and how big it is. Pure geometry so it can be tested
/// without a screen.
public enum PreviewThumbnailLayout {
    /// The largest box the image is scaled into, in points.
    public static let maxImageSize = CGSize(width: 240, height: 150)
    /// Quiet `space-3`.
    public static let padding: CGFloat = 12
    /// Tall enough for an icon with its key under it.
    public static let buttonRowHeight: CGFloat = 40
    /// The accent Copy button, labelled with its key.
    public static let copyButtonWidth: CGFloat = 84
    /// Save, Edit and Discard: icon over key.
    public static let buttonWidth: CGFloat = 44
    public static let buttonSpacing: CGFloat = 4
    /// Gap between the panel and the edges of the visible frame.
    public static let screenMargin: CGFloat = 16

    /// The image scaled to fit `maxImageSize`, keeping its aspect ratio. Never upscales and
    /// never returns a side smaller than one point.
    public static func imageSize(forPixelSize pixelSize: CGSize, backingScale: CGFloat) -> CGSize {
        let scale = max(backingScale, 1)
        let pointSize = CGSize(
            width: max(pixelSize.width, 1) / scale,
            height: max(pixelSize.height, 1) / scale
        )
        let fit = min(
            maxImageSize.width / pointSize.width,
            maxImageSize.height / pointSize.height,
            1
        )
        return CGSize(
            width: max((pointSize.width * fit).rounded(), 1),
            height: max((pointSize.height * fit).rounded(), 1)
        )
    }

    /// The width the four buttons need: Copy, a flexible gap, then three icon buttons, with
    /// `buttonSpacing` between each of those five children.
    public static var buttonRowWidth: CGFloat {
        let others = CGFloat(PreviewThumbnailAction.displayOrder.count - 1)
        return copyButtonWidth + others * buttonWidth + (others + 1) * buttonSpacing
    }

    /// The panel's frame in Cocoa screen coordinates: bottom-right of `visibleFrame`, which
    /// already excludes the Dock and the menu bar.
    public static func panelFrame(imageSize: CGSize, visibleFrame: CGRect) -> CGRect {
        let width = max(imageSize.width, buttonRowWidth) + padding * 2
        let height = imageSize.height + buttonRowHeight + padding * 3
        return CGRect(
            x: visibleFrame.maxX - width - screenMargin,
            y: visibleFrame.minY + screenMargin,
            width: width,
            height: height
        )
    }
}
