import CoreGraphics

/// Where the compact Settings panel sits (compact panels, decision 4). Pure geometry in Cocoa
/// screen coordinates, so it can be tested without a screen.
enum SettingsPanelLayout {
    /// The compact panel's width; the expanded tabs use `SettingsPage.width`.
    static let compactWidth: CGFloat = 380
    /// Gap between the menu bar icon and the panel's top edge.
    static let gapBelowAnchor: CGFloat = QuietTokens.space1
    /// What the expanded panel adds above a page: the tab strip and its line, with room spare.
    static let tabStripAllowance: CGFloat = 64

    /// The tallest a page may be so the expanded panel fits `visible` (never under 200).
    static func pageMaxHeight(within visible: CGRect, cap: CGFloat) -> CGFloat {
        max(200, min(cap, visible.height - gapBelowAnchor - tabStripAllowance))
    }

    /// Under the menu bar icon (`anchor`), right edges lined up, kept inside `visible`. Without
    /// an anchor, the top right of the screen.
    static func frame(size: CGSize, anchor: CGRect?, visible: CGRect) -> CGRect {
        let right = anchor?.maxX ?? visible.maxX - gapBelowAnchor
        let top = (anchor?.minY ?? visible.maxY) - gapBelowAnchor
        let frame = CGRect(x: right - size.width, y: top - size.height, width: size.width, height: size.height)
        return clamped(frame, within: visible)
    }

    /// The panel at a new size with its top-right corner kept, so it grows to the left and down
    /// from the menu bar icon, kept inside `visible`.
    static func resized(_ frame: CGRect, to size: CGSize, within visible: CGRect) -> CGRect {
        let resized = CGRect(x: frame.maxX - size.width, y: frame.maxY - size.height, width: size.width, height: size.height)
        return clamped(resized, within: visible)
    }

    /// Kept inside `visible`, and never taller or wider than it.
    static func clamped(_ frame: CGRect, within visible: CGRect) -> CGRect {
        var result = frame
        result.size.width = min(result.width, visible.width)
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.minX, visible.minX), max(visible.maxX - result.width, visible.minX))
        result.origin.y = min(max(result.minY, visible.minY), max(visible.maxY - result.height, visible.minY))
        return result
    }
}
