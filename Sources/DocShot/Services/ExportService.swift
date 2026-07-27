import Foundation
import CoreGraphics

/// Why an export produced no PNG data.
public enum ExportError: Error, Equatable, Sendable, LocalizedError {
    case sizing(ExportSizeError)
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .sizing(let error):
            return error.errorDescription
        case .renderFailed:
            return "Failed to render screenshot."
        }
    }
}

public final class ExportService: @unchecked Sendable {
    public static let shared = ExportService()

    private init() {}

    /// Production export boundary: renders flattened PNG off the main actor in a detached task.
    /// `exportSize` is applied to the flattened (post-crop) image at export time only.
    public func exportPNG(
        baseImage: CGImage,
        annotations: [AnnotationItem],
        cropRect: CGRect?,
        exportSize: ExportSize = .native
    ) async -> Data? {
        let result = await exportPNGResult(
            baseImage: baseImage,
            annotations: annotations,
            cropRect: cropRect,
            exportSize: exportSize
        )
        return try? result.get()
    }

    /// Same pipeline as `exportPNG`, surfacing why an export failed so callers can explain it.
    public func exportPNGResult(
        baseImage: CGImage,
        annotations: [AnnotationItem],
        cropRect: CGRect?,
        exportSize: ExportSize = .native
    ) async -> Result<Data, ExportError> {
        let flattenedSize = ImageRenderer.flattenedPixelSize(
            baseWidth: baseImage.width,
            baseHeight: baseImage.height,
            cropRect: cropRect
        )

        let outputSize: CGSize
        switch exportSize.resolve(sourceSize: flattenedSize) {
        case .success(let size):
            outputSize = size
        case .failure(let error):
            return .failure(.sizing(error))
        }

        // A native-sized export skips resampling entirely and stays byte-identical to V1 output.
        let resampleTarget: CGSize? = (outputSize == flattenedSize) ? nil : outputSize

        let data = await Task.detached(priority: .userInitiated) {
            return ImageRenderer.shared.renderFlattenedPNG(
                baseImage: baseImage,
                annotations: annotations,
                cropRect: cropRect,
                outputSize: resampleTarget
            )
        }.value

        guard let data else { return .failure(.renderFailed) }
        return .success(data)
    }
}
