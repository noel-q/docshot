import Testing
import CoreGraphics
import AppKit
@testable import DocShot

@Suite("EditorViewModel Tests")
struct EditorViewModelTests {
    
    private func createBlankImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 200,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 800,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
    
    @Test("Adding annotation and undo/redo")
    @MainActor
    func testAddAnnotationUndoRedo() {
        let image = createBlankImage()
        let vm = EditorViewModel(baseImage: image)
        
        #expect(vm.annotations.isEmpty)
        #expect(!vm.canUndo)
        
        let item = AnnotationItem(
            type: .rectangle(rect: CGRect(x: 10, y: 10, width: 40, height: 40), isFilled: false),
            color: .green,
            strokeWidth: 2.0
        )
        
        vm.addAnnotation(item)
        
        #expect(vm.annotations.count == 1)
        #expect(vm.selectedAnnotationID == item.id)
        #expect(vm.canUndo)
        
        vm.undo()
        
        #expect(vm.annotations.isEmpty)
        #expect(vm.selectedAnnotationID == nil)
        #expect(vm.canRedo)
        
        vm.redo()
        
        #expect(vm.annotations.count == 1)
        #expect(vm.selectedAnnotationID == item.id)
    }
    
    @Test("Single transaction move undo")
    @MainActor
    func testMoveAnnotationSingleTransactionUndo() {
        let image = createBlankImage()
        let vm = EditorViewModel(baseImage: image)
        
        let initialItem = AnnotationItem(
            type: .rectangle(rect: CGRect(x: 10, y: 10, width: 40, height: 40), isFilled: false),
            color: .red,
            strokeWidth: 2.0
        )
        
        vm.addAnnotation(initialItem)
        let initialUndoCount = vm.canUndo
        #expect(initialUndoCount)
        
        // Perform 5 incremental visual drag translations (does NOT add undo entries)
        for _ in 1...5 {
            vm.translateAnnotationLive(id: initialItem.id, delta: CGSize(width: 5, height: 5))
        }
        
        guard let movedItem = vm.annotations.first(where: { $0.id == initialItem.id }) else {
            Issue.record("Missing annotation")
            return
        }
        #expect(movedItem.boundingBox.origin.x == 35)
        #expect(movedItem.boundingBox.origin.y == 35)
        
        // Commit single transaction on drag end
        vm.commitMoveAnnotation(id: initialItem.id, from: initialItem, to: movedItem)
        
        // Undo move -> returns strictly to initial pre-drag position in ONE step!
        vm.undo()
        
        guard let undoneItem = vm.annotations.first(where: { $0.id == initialItem.id }) else {
            Issue.record("Missing annotation")
            return
        }
        #expect(undoneItem.boundingBox.origin.x == 10)
        #expect(undoneItem.boundingBox.origin.y == 10)
    }
    
    @Test("Deleting selection and undo")
    @MainActor
    func testDeleteSelectionUndo() {
        let image = createBlankImage()
        let vm = EditorViewModel(baseImage: image)
        
        let item = AnnotationItem(
            type: .text(rect: CGRect(x: 0, y: 0, width: 50, height: 20), text: "Test", fontSize: 14),
            color: .red,
            strokeWidth: 1.0
        )
        
        vm.addAnnotation(item)
        #expect(vm.annotations.count == 1)
        
        vm.deleteSelectedAnnotation()
        #expect(vm.annotations.isEmpty)

        vm.undo()
        #expect(vm.annotations.count == 1)
    }

    // MARK: - Export Size

    @Test("A new capture starts at native size and reports the capture's own dimensions")
    @MainActor
    func testExportSizeDefaultsToNativePerCapture() {
        let vm = EditorViewModel(baseImage: createBlankImage())

        #expect(vm.exportSize == .native)
        #expect(vm.flattenedPixelSize == CGSize(width: 200, height: 200))
        #expect(vm.resolvedExportSizeLabel == "200 × 200")
        #expect(vm.exportSizeErrorMessage == nil)

        // A second capture builds a fresh view model, so a size chosen earlier cannot leak into it.
        vm.exportSize = .percent(200)
        let nextCapture = EditorViewModel(baseImage: createBlankImage())
        #expect(nextCapture.exportSize == .native)
    }

    @Test("Resetting returns the export size to native")
    @MainActor
    func testResetExportSize() {
        let vm = EditorViewModel(baseImage: createBlankImage())

        vm.exportSize = .pixels(width: 640, height: 480)
        #expect(vm.resolvedExportSizeLabel == "640 × 480")

        vm.resetExportSize()
        #expect(vm.exportSize == .native)
        #expect(vm.resolvedExportSizeLabel == "200 × 200")
    }

    @Test("Resolved dimensions follow both the crop and the chosen size")
    @MainActor
    func testResolvedSizeFollowsCropAndSelection() {
        let vm = EditorViewModel(baseImage: createBlankImage())

        vm.setCropRect(CGRect(x: 50, y: 50, width: 100, height: 100))
        #expect(vm.flattenedPixelSize == CGSize(width: 100, height: 100))
        #expect(vm.resolvedExportSizeLabel == "100 × 100")

        vm.exportSize = .percent(50)
        #expect(vm.resolvedExportSizeLabel == "50 × 50")

        // Undoing the crop re-resolves against the full image without touching the export size.
        vm.undo()
        #expect(vm.exportSize == .percent(50))
        #expect(vm.resolvedExportSizeLabel == "100 × 100")
    }

    @Test("An invalid export size reports inline instead of producing a label")
    @MainActor
    func testInvalidExportSizeSurfacesMessage() {
        let vm = EditorViewModel(baseImage: createBlankImage())

        vm.exportSize = .pixels(width: 0, height: 480)
        #expect(vm.resolvedExportSizeLabel == nil)
        #expect(vm.exportSizeErrorMessage == ExportSizeError.invalidRequestedSize.errorDescription)

        vm.exportSize = .pixels(width: 30_000, height: 30_000)
        #expect(vm.resolvedExportSizeLabel == nil)
        #expect(vm.exportSizeErrorMessage?.contains("export limit") == true)

        vm.resetExportSize()
        #expect(vm.exportSizeErrorMessage == nil)
    }

    @Test("Choosing an export size is an output setting, not an undoable canvas edit")
    @MainActor
    func testExportSizeIsNotUndoable() {
        let vm = EditorViewModel(baseImage: createBlankImage())

        vm.exportSize = .percent(50)

        #expect(!vm.canUndo)
        #expect(vm.exportSize == .percent(50))
    }
}
