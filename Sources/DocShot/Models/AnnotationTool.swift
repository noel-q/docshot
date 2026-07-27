import Foundation

public enum AnnotationTool: String, CaseIterable, Identifiable, Sendable {
    case select = "Select / Move"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case text = "Text"
    case highlighter = "Highlighter"
    case redaction = "Redaction"
    case crop = "Crop"
    
    public var id: String { rawValue }
    
    public var systemImage: String {
        switch self {
        case .select: return "arrow.triangle.2.circlepath"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "square"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .highlighter: return "pencil.tip"
        case .redaction: return "eye.slash"
        case .crop: return "crop"
        }
    }
}
