import CoreGraphics

/// Where a floating image sits (C4b). Pure geometry in Cocoa screen coordinates, so it is tested.
enum FloatLayout {
    /// The longest side a float opens at, in points.
    static let maxSide: CGFloat = 480
    /// Each further float steps down and right by this much from the one before.
    static let cascade: CGFloat = 24

    /// The image's size in points (pixels over the backing scale), fitted inside `maxSide` and
    /// the visible frame, never enlarged, never under one point.
    static func size(pixelSize: CGSize, backingScale: CGFloat, visible: CGRect) -> CGSize {
        let scale = max(backingScale, 1)
        let points = CGSize(width: max(pixelSize.width, 1) / scale, height: max(pixelSize.height, 1) / scale)
        let limit = min(maxSide, visible.width * 0.8, visible.height * 0.8)
        let fit = min(limit / points.width, limit / points.height, 1)
        return CGSize(width: max((points.width * fit).rounded(), 1), height: max((points.height * fit).rounded(), 1))
    }

    /// Centred on `visible`, then `index` cascade steps down and right, kept inside `visible`.
    static func frame(size: CGSize, visible: CGRect, index: Int) -> CGRect {
        let step = cascade * CGFloat(index % 10)
        var frame = CGRect(
            x: (visible.midX - size.width / 2 + step).rounded(),
            y: (visible.midY - size.height / 2 - step).rounded(),
            width: size.width, height: size.height
        )
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }
}
