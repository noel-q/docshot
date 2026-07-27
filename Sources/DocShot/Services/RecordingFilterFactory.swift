import Foundation
import CoreGraphics
import CoreMedia
import ScreenCaptureKit

/// Turns a resolved `RecordingTarget` into the ScreenCaptureKit filter and configuration that
/// records exactly what the user selected.
///
/// The live `SCWindow`/`SCDisplay` is looked up here, immediately before the stream opens, so a
/// window that moved or closed since selection is caught rather than recorded at stale bounds.
enum RecordingFilterFactory {
    struct Resolved {
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
        let pixelSize: CGSize
    }

    /// Sample queue depth. Deeper queues buy latency tolerance at the cost of memory; the
    /// architecture contract caps this at 8 and defaults to 5.
    static let queueDepth = 5

    static func resolve(target: RecordingTarget, options: RecordingOptions) async throws -> Resolved {
        guard options.supportsCurrentAudioPipeline else {
            throw RecordingFailure.streamStart("Microphone and combined audio are not available yet.")
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw RecordingFailure.streamStart(error.localizedDescription)
        }

        switch target {
        case .window(let id, let boundsInCG):
            return try resolveWindow(id: id, boundsInCG: boundsInCG, content: content, options: options)
        case .region(let displayID, let rectInDisplay, let outputSize):
            return try resolveRegion(
                displayID: displayID,
                rectInDisplay: rectInDisplay,
                outputSize: outputSize,
                content: content,
                options: options
            )
        }
    }

    // MARK: - Targets

    private static func resolveWindow(
        id: CGWindowID,
        boundsInCG: CGRect,
        content: SCShareableContent,
        options: RecordingOptions
    ) throws -> Resolved {
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw RecordingFailure.invalidTarget(.windowUnavailable)
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)

        // The filter reports the content it will actually deliver. Fall back to the bounds
        // observed at selection time only if it reports nothing usable.
        let scale = CGFloat(filter.pointPixelScale)
        let contentRect = filter.contentRect
        let pointSize = (contentRect.width >= 1 && contentRect.height >= 1)
            ? contentRect.size
            : boundsInCG.size
        let effectiveScale = scale >= 1 ? scale : 1

        let pixelSize = CGSize(
            width: (pointSize.width * effectiveScale).rounded(),
            height: (pointSize.height * effectiveScale).rounded()
        )
        guard pixelSize.width >= 1, pixelSize.height >= 1 else {
            throw RecordingFailure.invalidTarget(.tooSmall)
        }

        let configuration = makeConfiguration(pixelSize: pixelSize, options: options)
        return Resolved(filter: filter, configuration: configuration, pixelSize: pixelSize)
    }

    private static func resolveRegion(
        displayID: CGDirectDisplayID,
        rectInDisplay: CGRect,
        outputSize: CGSize,
        content: SCShareableContent,
        options: RecordingOptions
    ) throws -> Resolved {
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw RecordingFailure.invalidTarget(.noContainingDisplay)
        }

        // Exclude DocShot itself so the menu bar's Stop control — and any other DocShot window —
        // stays out of the recorded pixels.
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        let ownApplications = content.applications.filter { $0.processID == ownProcessID }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: []
        )

        let configuration = makeConfiguration(pixelSize: outputSize, options: options)
        configuration.sourceRect = rectInDisplay

        return Resolved(filter: filter, configuration: configuration, pixelSize: outputSize)
    }

    // MARK: - Configuration

    private static func makeConfiguration(
        pixelSize: CGSize,
        options: RecordingOptions
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(max(options.maximumFrameRate, 1))
        )
        configuration.queueDepth = queueDepth
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = options.showsCursor
        configuration.scalesToFit = false

        // Excluding DocShot's applications from the content filter keeps its windows out of the
        // *video* only. System audio is captured globally — for a window target as much as a
        // display one — so DocShot's own alert sounds and error beeps have to be excluded here or
        // they land in the user's recording. `excludesCurrentProcessAudio` defaults to false.
        configuration.capturesAudio = options.capturesSystemAudio
        configuration.excludesCurrentProcessAudio = options.excludesOwnProcessAudio

        return configuration
    }
}
