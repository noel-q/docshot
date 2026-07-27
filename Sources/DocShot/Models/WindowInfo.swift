import Foundation
import CoreGraphics

public struct WindowInfo: Identifiable, Sendable, Equatable {
    public let id: CGWindowID
    public let boundsInCG: CGRect
    public let ownerName: String
    public let title: String
    public let layer: Int
    public let pid: pid_t
    
    public init(
        id: CGWindowID,
        boundsInCG: CGRect,
        ownerName: String,
        title: String,
        layer: Int,
        pid: pid_t
    ) {
        self.id = id
        self.boundsInCG = boundsInCG
        self.ownerName = ownerName
        self.title = title
        self.layer = layer
        self.pid = pid
    }
}
