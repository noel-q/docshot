import Foundation
import CoreGraphics

/// Why a requested export size could not be turned into concrete output pixel dimensions.
public enum ExportSizeError: Error, Equatable, Sendable, LocalizedError {
    /// The image being exported reported non-positive or non-finite pixel dimensions.
    case invalidSourceSize
    /// The requested percentage or pixel dimensions were non-positive or non-finite.
    case invalidRequestedSize
    /// The requested dimensions would allocate more decoded pixels than DocShot permits.
    case exceedsMemoryBudget(requestedPixelCount: Int, budgetPixelCount: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidSourceSize:
            return "The screenshot has no valid pixel dimensions to resize from."
        case .invalidRequestedSize:
            return "Enter a size larger than zero."
        case .exceedsMemoryBudget(let requested, let budget):
            return "That size needs \(requested) pixels, above DocShot's \(budget) pixel export limit."
        }
    }
}

/// An explicit output size for an export. Resizing is applied only at Copy/Save; the editor
/// always keeps the capture at its native resolution.
public enum ExportSize: Equatable, Sendable {
    /// Export at the flattened image's own pixel dimensions. No resampling occurs.
    case native
    /// Export at a percentage of the flattened image, where `100` is native size.
    case percent(Double)
    /// Export at explicit pixel dimensions.
    case pixels(width: Double, height: Double)

    /// Decoded-pixel memory budget for a single export (512 MB at 4 bytes per pixel).
    public static let memoryBudgetBytes = 512 * 1024 * 1024
    public static let bytesPerPixel = 4
    /// Largest number of output pixels an export may allocate: 134,217,728 (~11,585 x 11,585).
    public static let maximumPixelCount = ExportSize.memoryBudgetBytes / ExportSize.bytesPerPixel

    public var isNative: Bool {
        self == .native
    }

    /// Turns this size into concrete output pixel dimensions for a given flattened source size.
    ///
    /// Dimensions are rounded half-up and never fall below 1 px. `.native` is always accepted:
    /// the image already exists at that size, so it is not subject to the export memory budget.
    public func resolve(sourceSize: CGSize) -> Result<CGSize, ExportSizeError> {
        let sourceWidth = Double(sourceSize.width)
        let sourceHeight = Double(sourceSize.height)

        guard sourceWidth.isFinite, sourceHeight.isFinite, sourceWidth > 0, sourceHeight > 0 else {
            return .failure(.invalidSourceSize)
        }

        let requestedWidth: Double
        let requestedHeight: Double

        switch self {
        case .native:
            return .success(CGSize(
                width: ExportSize.roundedPixels(sourceWidth),
                height: ExportSize.roundedPixels(sourceHeight)
            ))

        case .percent(let percent):
            guard percent.isFinite, percent > 0 else { return .failure(.invalidRequestedSize) }
            requestedWidth = sourceWidth * percent / 100.0
            requestedHeight = sourceHeight * percent / 100.0

        case .pixels(let width, let height):
            guard width.isFinite, height.isFinite, width > 0, height > 0 else {
                return .failure(.invalidRequestedSize)
            }
            requestedWidth = width
            requestedHeight = height
        }

        let outputWidth = ExportSize.roundedPixels(requestedWidth)
        let outputHeight = ExportSize.roundedPixels(requestedHeight)
        let pixelCount = outputWidth * outputHeight

        guard pixelCount <= Double(ExportSize.maximumPixelCount) else {
            let reported = pixelCount < Double(Int.max) ? Int(pixelCount) : Int.max
            return .failure(.exceedsMemoryBudget(
                requestedPixelCount: reported,
                budgetPixelCount: ExportSize.maximumPixelCount
            ))
        }

        return .success(CGSize(width: outputWidth, height: outputHeight))
    }

    /// Rounds a pixel dimension half-up and clamps it to at least one pixel.
    public static func roundedPixels(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return max(1, value.rounded(.toNearestOrAwayFromZero))
    }

    /// The height that preserves `sourceSize`'s aspect ratio for a chosen output width.
    public static func aspectLockedHeight(forWidth width: Double, sourceSize: CGSize) -> Double? {
        let sourceWidth = Double(sourceSize.width)
        let sourceHeight = Double(sourceSize.height)
        guard width.isFinite, width > 0,
              sourceWidth.isFinite, sourceHeight.isFinite,
              sourceWidth > 0, sourceHeight > 0 else { return nil }
        return roundedPixels(width * sourceHeight / sourceWidth)
    }

    /// The width that preserves `sourceSize`'s aspect ratio for a chosen output height.
    public static func aspectLockedWidth(forHeight height: Double, sourceSize: CGSize) -> Double? {
        let sourceWidth = Double(sourceSize.width)
        let sourceHeight = Double(sourceSize.height)
        guard height.isFinite, height > 0,
              sourceWidth.isFinite, sourceHeight.isFinite,
              sourceWidth > 0, sourceHeight > 0 else { return nil }
        return roundedPixels(height * sourceWidth / sourceHeight)
    }
}
