import Foundation
import CoreGraphics
import AppKit

public final class WindowDiscoveryService: @unchecked Sendable {
    public static let shared = WindowDiscoveryService()
    
    private init() {}
    
    /// Queries visible windows from macOS and returns filtered list of selectable app windows.
    public func getEligibleWindows(excludedWindowIDs: Set<CGWindowID> = []) -> [WindowInfo] {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        let currentPID = NSRunningApplication.current.processIdentifier
        var results: [WindowInfo] = []
        
        for dict in windowInfoList {
            guard let windowID = dict[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard !excludedWindowIDs.contains(windowID) else { continue }
            
            guard let pid = dict[kCGWindowOwnerPID as String] as? pid_t, pid != currentPID else { continue }
            
            // Filter transparent or invisible helper windows
            if let alpha = dict[kCGWindowAlpha as String] as? Double, alpha < 0.1 { continue }
            if let isOnScreen = dict[kCGWindowIsOnscreen as String] as? Bool, !isOnScreen { continue }
            
            let layer = (dict[kCGWindowLayer as String] as? Int) ?? 0
            // Only normal windows on layer 0 are selectable application windows
            guard layer == 0 else { continue }
            
            let ownerName = (dict[kCGWindowOwnerName as String] as? String) ?? ""
            let systemOwners: Set<String> = [
                "Dock", "Window Server", "SystemUIServer", "NotificationCenter",
                "ControlCenter", "Wallpaper", "Spotlight", "Finder Desktop"
            ]
            if systemOwners.contains(ownerName) { continue }
            
            guard let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            
            // Filter tiny windows
            guard bounds.width >= 20 && bounds.height >= 20 else { continue }
            
            let title = (dict[kCGWindowName as String] as? String) ?? ""
            
            let windowInfo = WindowInfo(
                id: windowID,
                boundsInCG: bounds,
                ownerName: ownerName,
                title: title,
                layer: layer,
                pid: pid
            )
            results.append(windowInfo)
        }
        
        return results
    }
}
