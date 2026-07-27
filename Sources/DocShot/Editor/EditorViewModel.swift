import Foundation
import CoreGraphics
import AppKit
import SwiftUI

@MainActor
public final class EditorViewModel: ObservableObject {
    @Published public var baseImage: CGImage
    @Published public var annotations: [AnnotationItem] = []
    @Published public var selectedAnnotationID: UUID?
    @Published public var activeTool: AnnotationTool = .arrow
    @Published public var selectedColor: CodableColor = .red
    @Published public var selectedStrokeWidth: CGFloat = 4.0
    @Published public var redactionStyle: RedactionStyle = .blur
    @Published public var cropRect: CGRect?

    /// Output size for the next Copy/Save. Editing always stays at native resolution, and this
    /// is deliberately not undoable and not persisted: every capture starts at `.native`.
    @Published public var exportSize: ExportSize = .native

    public let undoManager = UndoManager()
    
    public init(baseImage: CGImage) {
        self.baseImage = baseImage
        self.undoManager.groupsByEvent = false
    }
    
    // MARK: - Annotation Operations
    
    public func addAnnotation(_ item: AnnotationItem) {
        undoManager.beginUndoGrouping()
        self.annotations.append(item)
        self.selectedAnnotationID = item.id
        
        undoManager.registerUndo(withTarget: self) { target in
            target.deleteAnnotation(id: item.id)
        }
        undoManager.setActionName("Add Annotation")
        undoManager.endUndoGrouping()
    }
    
    public func deleteAnnotation(id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let deletedItem = annotations[index]
        
        undoManager.beginUndoGrouping()
        self.annotations.remove(at: index)
        if self.selectedAnnotationID == id {
            self.selectedAnnotationID = nil
        }
        
        undoManager.registerUndo(withTarget: self) { target in
            target.addAnnotation(deletedItem)
        }
        undoManager.setActionName("Delete Annotation")
        undoManager.endUndoGrouping()
    }
    
    public func deleteSelectedAnnotation() {
        guard let selectedID = selectedAnnotationID else { return }
        deleteAnnotation(id: selectedID)
    }
    
    /// Live visual drag translation (does NOT touch UndoManager during drag)
    public func translateAnnotationLive(id: UUID, delta: CGSize) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        var item = annotations[index]
        item.translate(by: delta)
        annotations[index] = item
    }
    
    /// Commits a completed move as a SINGLE undoable transaction
    public func commitMoveAnnotation(id: UUID, from oldItem: AnnotationItem, to newItem: AnnotationItem) {
        guard oldItem != newItem else { return }
        
        undoManager.beginUndoGrouping()
        if let index = annotations.firstIndex(where: { $0.id == id }) {
            annotations[index] = newItem
        }
        
        undoManager.registerUndo(withTarget: self) { target in
            target.commitMoveAnnotation(id: id, from: newItem, to: oldItem)
        }
        undoManager.setActionName("Move Annotation")
        undoManager.endUndoGrouping()
    }
    
    public func updateAnnotation(_ item: AnnotationItem) {
        guard let index = annotations.firstIndex(where: { $0.id == item.id }) else { return }
        let oldItem = annotations[index]
        
        undoManager.beginUndoGrouping()
        self.annotations[index] = item
        
        undoManager.registerUndo(withTarget: self) { target in
            target.updateAnnotation(oldItem)
        }
        undoManager.setActionName("Update Annotation")
        undoManager.endUndoGrouping()
    }
    
    public func setCropRect(_ rect: CGRect?) {
        let oldCrop = self.cropRect
        
        undoManager.beginUndoGrouping()
        self.cropRect = rect
        
        undoManager.registerUndo(withTarget: self) { target in
            target.setCropRect(oldCrop)
        }
        undoManager.setActionName("Crop Image")
        undoManager.endUndoGrouping()
    }
    
    // MARK: - Export Size

    /// Pixel dimensions the current crop flattens to, before any export resizing.
    public var flattenedPixelSize: CGSize {
        ImageRenderer.flattenedPixelSize(
            baseWidth: baseImage.width,
            baseHeight: baseImage.height,
            cropRect: cropRect
        )
    }

    /// The output dimensions the current selection would produce, or why it cannot.
    public var resolvedExportSize: Result<CGSize, ExportSizeError> {
        exportSize.resolve(sourceSize: flattenedPixelSize)
    }

    /// Output dimensions to show before Copy/Save, e.g. "1920 × 1080". Nil when the size is invalid.
    public var resolvedExportSizeLabel: String? {
        guard case .success(let size) = resolvedExportSize else { return nil }
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    /// A human-readable reason the current export size cannot be used, if any.
    public var exportSizeErrorMessage: String? {
        guard case .failure(let error) = resolvedExportSize else { return nil }
        return error.errorDescription
    }

    /// Returns the export size to native. Called for every new capture; a new editor session
    /// already constructs a fresh view model, so this exists for explicit in-session resets.
    public func resetExportSize() {
        exportSize = .native
    }

    // MARK: - Undo / Redo Helpers
    
    public var canUndo: Bool {
        undoManager.canUndo
    }
    
    public var canRedo: Bool {
        undoManager.canRedo
    }
    
    public func undo() {
        if undoManager.canUndo {
            undoManager.undo()
        }
    }
    
    public func redo() {
        if undoManager.canRedo {
            undoManager.redo()
        }
    }
    
    // MARK: - Export Flattened PNG Data
    
    /// Renders the export image away from the UI actor so large Retina captures do not stall the editor.
    /// Routed through ExportService so it honours the selected export size like Copy and Save do.
    public func renderPNGData() async -> Data? {
        return await ExportService.shared.exportPNG(
            baseImage: baseImage,
            annotations: annotations,
            cropRect: cropRect,
            exportSize: exportSize
        )
    }
}
