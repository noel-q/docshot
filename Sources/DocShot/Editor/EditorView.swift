import SwiftUI
import AppKit

public struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    public var onClose: () -> Void
    
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false
    @State private var isExporting: Bool = false
    @State private var outputStatus: String?
    @State private var exportIssue: String?
    
    public init(viewModel: EditorViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }
    
    private let availableColors: [CodableColor] = [
        .red, .green, .blue, .yellow, .orange, .white, .black
    ]
    
    private let availableWidths: [CGFloat] = [2.0, 4.0, 6.0, 8.0]
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            HStack(spacing: 12) {
                // Annotation Tools
                HStack(spacing: 4) {
                    ForEach(AnnotationTool.allCases) { tool in
                        Button(action: {
                            viewModel.activeTool = tool
                        }) {
                            Image(systemName: tool.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 28, height: 26)
                                .foregroundColor(viewModel.activeTool == tool ? DesignTokens.primaryAccent : .primary)
                        }
                        .buttonStyle(.plain)
                        .background(viewModel.activeTool == tool ? DesignTokens.primaryAccent.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(viewModel.activeTool == tool ? DesignTokens.primaryAccent : Color.clear, lineWidth: 1)
                        )
                        .help(tool.rawValue)
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 8).fill(DesignTokens.cardBackground))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DesignTokens.borderAdaptive, lineWidth: 1))
                
                Divider()
                    .frame(height: 20)
                
                // Color Picker Presets
                HStack(spacing: 6) {
                    ForEach(availableColors.indices, id: \.self) { index in
                        let color = availableColors[index]
                        Circle()
                            .fill(color.swiftUIColor)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: viewModel.selectedColor == color ? 2 : 0)
                            )
                            .overlay(
                                Circle()
                                    .stroke(DesignTokens.borderSubtle, lineWidth: 1)
                            )
                            .onTapGesture {
                                viewModel.selectedColor = color
                            }
                    }
                }
                
                Divider()
                    .frame(height: 20)
                
                // Line Widths
                HStack(spacing: 6) {
                    ForEach(availableWidths, id: \.self) { w in
                        Button(action: {
                            viewModel.selectedStrokeWidth = w
                        }) {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: w * 1.5 + 4, height: w * 1.5 + 4)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 22, height: 22)
                        .background(viewModel.selectedStrokeWidth == w ? DesignTokens.primaryAccent.opacity(0.15) : Color.clear)
                        .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                // Undo / Redo / Delete
                HStack(spacing: 6) {
                    Button(action: { viewModel.undo() }) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!viewModel.canUndo)
                    .keyboardShortcut("z", modifiers: [.command])
                    .help("Undo (⌘Z)")
                    
                    Button(action: { viewModel.redo() }) {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!viewModel.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .help("Redo (⇧⌘Z)")
                    
                    Button(action: { viewModel.deleteSelectedAnnotation() }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .disabled(viewModel.selectedAnnotationID == nil)
                    .keyboardShortcut(.delete, modifiers: [])
                    .help("Delete Selection (Backspace/Delete)")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DesignTokens.windowBackground)
            
            Divider()
            
            // Center Canvas View
            CanvasView(viewModel: viewModel)
            
            Divider()
            
            // Bottom Action Bar: Copy, Save, Discard
            HStack(spacing: 16) {
                // Discard Button (Explicit Exit Path)
                Button(action: {
                    onClose()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                        Text("Discard")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DesignTokens.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .disabled(isExporting)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Discard screenshot (Esc)")
                
                ExportSizeControl(viewModel: viewModel)

                Spacer()

                if isExporting {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                } else if let issue = exportIssue ?? viewModel.exportSizeErrorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(issue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                } else if let outputStatus {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DesignTokens.primaryAccent)
                        Text(outputStatus)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignTokens.secondaryText)
                    }
                    .lineLimit(1)
                }
                
                // Save Button
                Button(action: {
                    performSave()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save...")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                }
                .disabled(isExporting)
                .keyboardShortcut("s", modifiers: [.command])
                .help("Save PNG to file (⌘S)")
                
                // Copy Button (Default Action)
                Button(action: {
                    performCopy()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy PNG")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(isExporting ? Color.gray : DesignTokens.primaryAccent)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(isExporting)
                .keyboardShortcut("c", modifiers: [.command])
                .help("Copy flattened PNG to clipboard (⌘C)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(DesignTokens.windowBackground)
        }
        .frame(minWidth: 700, minHeight: 500)
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Export Failure"),
                message: Text(errorMessage ?? "An error occurred while exporting image."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    /// Renders the export, or reports why it could not be produced. An invalid export size is
    /// reported inline next to the size control; only a genuine render failure raises an alert.
    private func renderExport() async -> Data? {
        let result = await ExportService.shared.exportPNGResult(
            baseImage: viewModel.baseImage,
            annotations: viewModel.annotations,
            cropRect: viewModel.cropRect,
            exportSize: viewModel.exportSize
        )

        switch result {
        case .success(let data):
            return data
        case .failure(.sizing(let sizingError)):
            self.exportIssue = sizingError.errorDescription
            return nil
        case .failure(.renderFailed):
            self.errorMessage = ExportError.renderFailed.errorDescription
            self.showErrorAlert = true
            return nil
        }
    }

    private func performCopy() {
        guard !isExporting else { return }
        isExporting = true
        outputStatus = nil
        exportIssue = nil

        Task {
            let pngData = await renderExport()
            self.isExporting = false

            guard let data = pngData else { return }

            if OutputService.shared.copyToClipboard(pngData: data) {
                // Show success status and retain editor window open (Discard is explicit exit path)
                self.outputStatus = "Copied to clipboard"
            } else {
                self.errorMessage = "Failed to copy screenshot to the clipboard."
                self.showErrorAlert = true
            }
        }
    }

    private func performSave() {
        guard !isExporting else { return }
        isExporting = true
        outputStatus = nil
        exportIssue = nil

        let parentWin = EditorWindowController.shared.currentWindow

        Task {
            let pngData = await renderExport()
            self.isExporting = false

            guard let data = pngData else { return }

            let result = await OutputService.shared.saveWithPanel(pngData: data, parentWindow: parentWin)
            switch result {
            case .saved(let url):
                // Show success status and retain editor window open (Discard is explicit exit path)
                self.outputStatus = "Saved \(url.lastPathComponent)"
            case .cancelled:
                break
            case .failed(let msg):
                self.errorMessage = msg
                self.showErrorAlert = true
            }
        }
    }
}
