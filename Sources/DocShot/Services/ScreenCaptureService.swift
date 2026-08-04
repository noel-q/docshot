import Foundation
import CoreGraphics
import ScreenCaptureKit
import AppKit

public enum CaptureError: Error, LocalizedError, Equatable {
    case permissionDenied
    case noDisplayFound
    case captureFailed(String)
    case compositingFailed
    
    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Screen Recording permission was denied."
        case .noDisplayFound: return "No connected screen display found for selection."
        case .captureFailed(let msg): return "Screen capture failed: \(msg)"
        case .compositingFailed: return "Failed to composite multi-display screenshot."
        }
    }
}

public final class ScreenCaptureService: @unchecked Sendable {
    public static let shared = ScreenCaptureService()
    
    private init() {}
    
    /// Returns user preference for cursor inclusion in screenshots (defaults to false).
    public var includeCursor: Bool {
        return UserDefaults.standard.bool(forKey: "DocShotIncludeCursor")
    }
    
    /// Bounded multi-display region capture with native pixel compositing.
    public func captureRegion(_ rectInCG: CGRect) async throws -> CGImage {
        // The selector and `CGWindowListCreateImage` both use the global Core Graphics
        // coordinate space. Prefer it for still regions so the rectangle the user sees is the
        // rectangle that is sampled. ScreenCaptureKit's `sourceRect` is display-local and has
        // produced shifted crops on some external-display arrangements.
        if !includeCursor, let image = captureCGWindowListImage(rectInCG: rectInCG) {
            return image
        }

        return try await captureRegionWithScreenCaptureKit(rectInCG)
    }

    /// ScreenCaptureKit fallback for cursor-inclusive captures and systems where the legacy
    /// Core Graphics capture API is unavailable.
    private func captureRegionWithScreenCaptureKit(_ rectInCG: CGRect) async throws -> CGImage {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw CaptureError.noDisplayFound }
        
        let mainScreenHeight = NSScreen.main?.frame.height ?? 1080
        
        // Map NSScreens to Core Graphics bounds, displayIDs, and backing scale factors
        let displaySegments = screens.compactMap { screen -> (screen: NSScreen, displayID: CGDirectDisplayID, cgFrame: CGRect, scale: CGFloat, intersection: CGRect)? in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            let cocoaFrame = screen.frame
            let cgFrame = DisplayGeometry.cocoaToCGRect(cocoaFrame, mainScreenHeight: mainScreenHeight)
            let intersection = cgFrame.intersection(rectInCG)
            guard !intersection.isNull, intersection.width > 1, intersection.height > 1 else { return nil }
            return (screen, displayID, cgFrame, screen.backingScaleFactor, intersection)
        }
        
        guard !displaySegments.isEmpty else {
            throw CaptureError.noDisplayFound
        }
        
        let targetScale = displaySegments.map(\.scale).max() ?? 2.0
        var capturedParts: [(image: CGImage, cgRect: CGRect)] = []
        
        // Atomic capture: fail immediately if any segment fails
        for segment in displaySegments {
            do {
                let partImage = try await captureDisplaySegment(segment.displayID, screen: segment.screen, segmentRectInCG: segment.intersection)
                capturedParts.append((partImage, segment.intersection))
            } catch {
                throw CaptureError.captureFailed("Failed to capture screen segment for display \(segment.displayID): \(error.localizedDescription)")
            }
        }
        
        guard capturedParts.count == displaySegments.count else {
            throw CaptureError.captureFailed("Multi-display capture incomplete.")
        }
        
        // If single display segment captured, return directly if bounds match
        if capturedParts.count == 1, let single = capturedParts.first, single.cgRect == rectInCG {
            return single.image
        }
        
        // Composite multi-display segments onto unified canvas
        let totalPixelWidth = Int(rectInCG.width * targetScale)
        let totalPixelHeight = Int(rectInCG.height * targetScale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: nil,
            width: totalPixelWidth,
            height: totalPixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: totalPixelWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CaptureError.compositingFailed
        }
        
        for (partImage, partCGRect) in capturedParts {
            let relativeX = (partCGRect.origin.x - rectInCG.origin.x) * targetScale
            let relativeY = (rectInCG.maxY - partCGRect.maxY) * targetScale
            let partWidth = partCGRect.width * targetScale
            let partHeight = partCGRect.height * targetScale
            
            let destRect = CGRect(x: relativeX, y: relativeY, width: partWidth, height: partHeight)
            context.draw(partImage, in: destRect)
        }
        
        guard let compositedImage = context.makeImage() else {
            throw CaptureError.compositingFailed
        }
        
        return compositedImage
    }
    
    private func captureDisplaySegment(_ displayID: CGDirectDisplayID, screen: NSScreen, segmentRectInCG: CGRect) async throws -> CGImage {
        if #available(macOS 14.0, *) {
            do {
                let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let scDisplay = shareable.displays.first(where: { $0.displayID == displayID }) else {
                    throw CaptureError.noDisplayFound
                }
                
                let filter = SCContentFilter(display: scDisplay, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                
                let relativeRect = CGRect(
                    x: segmentRectInCG.origin.x - CGFloat(scDisplay.frame.origin.x),
                    y: segmentRectInCG.origin.y - CGFloat(scDisplay.frame.origin.y),
                    width: segmentRectInCG.width,
                    height: segmentRectInCG.height
                )
                
                let scale = screen.backingScaleFactor
                config.sourceRect = relativeRect
                config.width = Int(relativeRect.width * scale)
                config.height = Int(relativeRect.height * scale)
                config.showsCursor = includeCursor // Respect cursor setting (default: false)
                
                return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            } catch {
                return try captureCGWindowListFallback(rectInCG: segmentRectInCG)
            }
        }
        
        return try captureCGWindowListFallback(rectInCG: segmentRectInCG)
    }
    
    /// Captures a single window by CGWindowID.
    public func captureWindow(windowID: CGWindowID, boundsInCG: CGRect) async throws -> CGImage {
        // A desktop-independent window capture has no display-local source rect, so it avoids
        // the offset problem that affects ScreenCaptureKit region captures. Request the output
        // at the owning display's backing scale; the default configuration otherwise returns a
        // 1x bitmap for some external displays.
        if #available(macOS 14.0, *) {
            do {
                let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                if let scWindow = shareable.windows.first(where: { $0.windowID == windowID }) {
                    let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                    let config = SCStreamConfiguration()
                    let scale = backingScale(forWindowBoundsInCG: boundsInCG)
                    config.width = max(1, Int((scWindow.frame.width * scale).rounded()))
                    config.height = max(1, Int((scWindow.frame.height * scale).rounded()))
                    config.showsCursor = includeCursor // Respect cursor setting (default: false)
                    
                    return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                }
            } catch {
                // Fallback
            }
        }
        
        if let cgImage = captureCGWindowListWindowFallback(windowID: windowID, boundsInCG: boundsInCG) {
            return cgImage
        }
        
        return try await captureRegion(boundsInCG)
    }

    /// Returns the scale at which a selected window should be rasterised. Window bounds from
    /// discovery are in global Core Graphics points, while the captured bitmap must use the
    /// owning display's backing pixels.
    private func backingScale(forWindowBoundsInCG bounds: CGRect) -> CGFloat {
        let mainScreenHeight = NSScreen.main?.frame.height ?? 1080
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        guard let screen = NSScreen.screens.first(where: { screen in
            DisplayGeometry.cocoaToCGRect(screen.frame, mainScreenHeight: mainScreenHeight).contains(center)
        }) else {
            return 1
        }

        return max(1, screen.backingScaleFactor)
    }
    
    // MARK: - Core Graphics Legacy Compatibility Fallbacks
    
    @available(macOS, deprecated: 14.0, message: "Use ScreenCaptureKit SCScreenshotManager on macOS 14+")
    private func captureCGWindowListFallback(rectInCG: CGRect) throws -> CGImage {
        if let cgImage = captureCGWindowListImage(rectInCG: rectInCG) {
            return cgImage
        }
        throw CaptureError.captureFailed("Legacy CoreGraphics region capture failed.")
    }

    @available(macOS, deprecated: 14.0, message: "Use ScreenCaptureKit SCScreenshotManager on macOS 14+")
    private func captureCGWindowListImage(rectInCG: CGRect) -> CGImage? {
        CGWindowListCreateImage(rectInCG, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
    }
    
    @available(macOS, deprecated: 14.0, message: "Use ScreenCaptureKit SCScreenshotManager on macOS 14+")
    private func captureCGWindowListWindowFallback(windowID: CGWindowID, boundsInCG: CGRect) -> CGImage? {
        return CGWindowListCreateImage(boundsInCG, .optionIncludingWindow, windowID, [.bestResolution, .boundsIgnoreFraming])
    }
}
