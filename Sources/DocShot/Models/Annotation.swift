import Foundation
import CoreGraphics
import SwiftUI

public enum RedactionStyle: String, Codable, Sendable, CaseIterable {
    case blur
    case pixelate
}

public struct CodableColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    public init(_ color: Color) {
        if let components = NSColor(color).usingColorSpace(.sRGB) {
            self.red = Double(components.redComponent)
            self.green = Double(components.greenComponent)
            self.blue = Double(components.blueComponent)
            self.alpha = Double(components.alphaComponent)
        } else {
            self.red = 1; self.green = 0; self.blue = 0; self.alpha = 1
        }
    }
    
    public var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
    
    public var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
    
    public static let red = CodableColor(red: 0.9, green: 0.2, blue: 0.2)
    public static let green = CodableColor(red: 0.2, green: 0.8, blue: 0.3)
    public static let blue = CodableColor(red: 0.2, green: 0.5, blue: 0.9)
    public static let yellow = CodableColor(red: 0.95, green: 0.8, blue: 0.1)
    public static let orange = CodableColor(red: 0.95, green: 0.5, blue: 0.1)
    public static let white = CodableColor(red: 1.0, green: 1.0, blue: 1.0)
    public static let black = CodableColor(red: 0.0, green: 0.0, blue: 0.0)
    public static let highlighterYellow = CodableColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 0.4)
}

public enum AnnotationType: Codable, Equatable, Sendable {
    case arrow(start: CGPoint, end: CGPoint)
    case rectangle(rect: CGRect, isFilled: Bool)
    case ellipse(rect: CGRect, isFilled: Bool)
    case text(rect: CGRect, text: String, fontSize: CGFloat)
    case highlighter(points: [CGPoint])
    case redaction(rect: CGRect, style: RedactionStyle)
}

public struct AnnotationItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var type: AnnotationType
    public var color: CodableColor
    public var strokeWidth: CGFloat
    
    public init(id: UUID = UUID(), type: AnnotationType, color: CodableColor = .red, strokeWidth: CGFloat = 3.0) {
        self.id = id
        self.type = type
        self.color = color
        self.strokeWidth = strokeWidth
    }
    
    /// Bounding rectangle for selection hit-testing and dragging.
    public var boundingBox: CGRect {
        switch type {
        case .arrow(let start, let end):
            let minX = min(start.x, end.x)
            let maxX = max(start.x, end.x)
            let minY = min(start.y, end.y)
            let maxY = max(start.y, end.y)
            return CGRect(x: minX, y: minY, width: max(maxX - minX, 10), height: max(maxY - minY, 10))
        case .rectangle(let rect, _), .ellipse(let rect, _), .redaction(let rect, _):
            return DisplayGeometry.normalizeRect(rect)
        case .text(let rect, _, _):
            return DisplayGeometry.normalizeRect(rect)
        case .highlighter(let points):
            guard let first = points.first else { return .zero }
            var minX = first.x; var maxX = first.x
            var minY = first.y; var maxY = first.y
            for p in points {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: max(maxX - minX, 10), height: max(maxY - minY, 10))
        }
    }
    
    /// Moves the annotation by a delta offset (dx, dy).
    public mutating func translate(by delta: CGSize) {
        switch type {
        case .arrow(let start, let end):
            type = .arrow(
                start: CGPoint(x: start.x + delta.width, y: start.y + delta.height),
                end: CGPoint(x: end.x + delta.width, y: end.y + delta.height)
            )
        case .rectangle(let rect, let isFilled):
            type = .rectangle(
                rect: CGRect(x: rect.origin.x + delta.width, y: rect.origin.y + delta.height, width: rect.width, height: rect.height),
                isFilled: isFilled
            )
        case .ellipse(let rect, let isFilled):
            type = .ellipse(
                rect: CGRect(x: rect.origin.x + delta.width, y: rect.origin.y + delta.height, width: rect.width, height: rect.height),
                isFilled: isFilled
            )
        case .text(let rect, let text, let fontSize):
            type = .text(
                rect: CGRect(x: rect.origin.x + delta.width, y: rect.origin.y + delta.height, width: rect.width, height: rect.height),
                text: text,
                fontSize: fontSize
            )
        case .highlighter(let points):
            let newPoints = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
            type = .highlighter(points: newPoints)
        case .redaction(let rect, let style):
            type = .redaction(
                rect: CGRect(x: rect.origin.x + delta.width, y: rect.origin.y + delta.height, width: rect.width, height: rect.height),
                style: style
            )
        }
    }
}
