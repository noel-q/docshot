import Foundation

public enum CaptureState: Equatable, Sendable {
    case idle
    case permissionRequired
    case selecting
    case capturing
    case editing
    case cancelled
}
