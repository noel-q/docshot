import Foundation
import CoreGraphics
import SwiftUI

/// Holds the colour currently under the cursor during selection.
///
/// This is deliberately a separate observable from `CaptureCoordinator`: the overlay's readout
/// chip re-renders when the sampled colour changes, without invalidating the whole selection
/// overlay on every mouse event. Updates are published only when the resolved pixel actually
/// changes, so sub-pixel cursor jitter costs nothing.
///
/// It holds exactly one sample at a time. Nothing is written to the clipboard, and no history
/// of sampled colours is kept.
@MainActor
public final class ColorReadoutModel: ObservableObject {
    @Published public private(set) var sample: ColorSample?
    @Published public private(set) var magnifierGrid: MagnifierGrid?
    /// True when the cursor is over a display that has no snapshot (skipped by the memory
    /// budget, or its capture failed).
    @Published public private(set) var isUnavailable: Bool = false

    /// Number of times a change was actually published. Used by tests to prove that repeated
    /// events on the same pixel do not churn the UI.
    public private(set) var publishedUpdateCount = 0

    private struct SampledPixel: Equatable {
        let displayID: CGDirectDisplayID
        let coordinate: PixelCoordinate
    }

    private var lastPixel: SampledPixel?

    public init() {}

    public func update(
        globalPoint: CGPoint,
        snapshots: [DisplaySnapshot],
        unavailableDescriptors: [DisplayDescriptor]
    ) {
        if let snapshot = snapshots.first(where: { $0.contains(globalPoint: globalPoint) }) {
            guard let coordinate = DisplayGeometry.pixelCoordinate(
                forGlobalCGPoint: globalPoint,
                displayFrameInCG: snapshot.descriptor.frameInCG,
                imageScale: snapshot.descriptor.scale
            ) else {
                clear()
                return
            }

            let pixel = SampledPixel(displayID: snapshot.descriptor.displayID, coordinate: coordinate)
            guard pixel != lastPixel else { return }

            lastPixel = pixel
            sample = snapshot.sample(atGlobalPoint: globalPoint)
            magnifierGrid = PixelSampler.sampleGrid(image: snapshot.image, at: coordinate)
            isUnavailable = false
            publishedUpdateCount += 1
            return
        }

        if unavailableDescriptors.contains(where: { $0.contains(globalPoint: globalPoint) }) {
            guard !isUnavailable || sample != nil || magnifierGrid != nil else { return }
            lastPixel = nil
            sample = nil
            magnifierGrid = nil
            isUnavailable = true
            publishedUpdateCount += 1
            return
        }

        clear()
    }

    /// Clears the readout. Called when selection ends and before a refresh re-captures.
    public func clear() {
        guard sample != nil || isUnavailable || lastPixel != nil || magnifierGrid != nil else { return }
        lastPixel = nil
        sample = nil
        magnifierGrid = nil
        isUnavailable = false
        publishedUpdateCount += 1
    }

    // MARK: - Display strings

    public var hexText: String { sample?.hexString ?? "—" }
    public var rgbText: String { sample?.rgbString ?? "—" }
    public var hslText: String { sample?.hslString ?? "—" }

    public var swatchColor: Color? {
        guard let sample else { return nil }
        return Color(
            .sRGB,
            red: Double(sample.red) / 255.0,
            green: Double(sample.green) / 255.0,
            blue: Double(sample.blue) / 255.0,
            opacity: 1.0
        )
    }
}
