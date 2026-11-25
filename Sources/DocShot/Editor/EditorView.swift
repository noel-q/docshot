import SwiftUI
import AppKit

public struct EditorView: View {
    /// Redraws this view when the colour theme changes (C0.7).
    @ObservedObject private var themeController = ThemeController.shared
    @ObservedObject var viewModel: EditorViewModel
    public var onClose: () -> Void
    
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false
    @State private var isExporting: Bool = false
    @State private var outputStatus: String?
    @State private var exportIssue: String?
    @State private var keyMonitor: Any?
    
    public init(viewModel: EditorViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            QuietRule()
            // The image sits on the canvas, the bars on surface (image editor in Quiet).
            CanvasView(viewModel: viewModel)
                .padding(Quiet.Space.s6)
                .background(Quiet.canvas)
            QuietRule()
            actionBar
        }
        .frame(minWidth: 700, minHeight: 500)
        // Behind the see-through rules, so they blend as `line` should.
        .background(Quiet.surface)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Could not export"),
                message: Text(errorMessage ?? "Something went wrong while exporting the image."),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: Toolbar

    /// Tools, colours, widths, then undo, redo and delete. Selection is neutral: `selection`
    /// behind, `ink` in front; the accent stays for Copy.
    private var toolbar: some View {
        HStack(spacing: Quiet.Space.s3) {
            AnnotationStyleBar(
                activeTool: $viewModel.activeTool,
                color: $viewModel.selectedColor,
                width: $viewModel.selectedStrokeWidth,
                showsToolKeys: true
            )

            Spacer(minLength: 0)

            HStack(spacing: Quiet.Space.s1) {
                EditorIconButton("arrow.uturn.backward", help: "Undo (⌘Z)", disabled: !viewModel.canUndo) { viewModel.undo() }
                    .keyboardShortcut("z", modifiers: [.command])
                EditorIconButton("arrow.uturn.forward", help: "Redo (⇧⌘Z)", disabled: !viewModel.canRedo) { viewModel.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                EditorIconButton("trash", help: "Delete the selected mark (⌫)", disabled: viewModel.selectedAnnotationID == nil) {
                    viewModel.deleteSelectedAnnotation()
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
        }
        .padding(.horizontal, Quiet.Space.s4)
        .padding(.vertical, Quiet.Space.s2)
        .background(Quiet.surface)
    }

    // MARK: Action bar

    /// Discard and the size on the left; the result, Save and the one accent button, Copy, on
    /// the right, each with its key.
    private var actionBar: some View {
        HStack(spacing: Quiet.Space.s3) {
            Button(action: onClose) {
                HStack(spacing: Quiet.Space.s1) {
                    KeyHint(keys: "esc")
                    Text("Discard").font(Quiet.Font.ui).foregroundStyle(Quiet.inkMuted)
                }
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Discard the screenshot (esc)")
            .accessibilityLabel("Discard")

            ExportSizeControl(viewModel: viewModel)

            Spacer(minLength: Quiet.Space.s2)

            if isExporting {
                ProgressView()
                    .controlSize(.small)
            } else if let issue = exportIssue ?? viewModel.exportSizeErrorMessage {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(Quiet.Font.caption)
                    .foregroundStyle(Quiet.danger)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let outputStatus {
                Label(outputStatus, systemImage: "checkmark")
                    .font(Quiet.Font.caption)
                    .foregroundStyle(Quiet.inkMuted)
                    .lineLimit(1)
            }

            Button(action: performSave) {
                Text("Save…  ⌘S")
            }
            .controlSize(.large)
            .disabled(isExporting)
            .keyboardShortcut("s", modifiers: [.command])
            .help("Save a PNG (⌘S)")
            .accessibilityLabel("Save")

            Button {
                performCopy()
            } label: {
                AccentButtonLabel("Copy  ↵")
            }
            .buttonStyle(.borderedProminent)
            .tint(Quiet.accent)
            .controlSize(.large)
            .disabled(isExporting)
            .keyboardShortcut("c", modifiers: [.command])
            .help("Copy the PNG (⌘C). Return copies and closes.")
            .accessibilityLabel("Copy")
        }
        .padding(.horizontal, Quiet.Space.s4)
        .padding(.vertical, Quiet.Space.s3)
        .background(Quiet.surface)
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

    /// Tool keys and Return act only while the canvas has focus: the editor window is key,
    /// nothing is presented over it, and no text field is being edited.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard let window = EditorWindowController.shared.currentWindow,
                  event.window === window,
                  window.attachedSheet == nil,
                  !isExporting else {
                return event
            }

            let command = EditorKeyCommand.resolve(
                characters: event.charactersIgnoringModifiers,
                keyCode: event.keyCode,
                hasCommandModifiers: !event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                isEditingText: window.firstResponder is NSText
            )

            switch command {
            case .selectTool(let tool):
                viewModel.activeTool = tool
                return nil
            case .copyAndClose:
                performCopy(closeOnSuccess: true)
                return nil
            case nil:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func performCopy(closeOnSuccess: Bool = false) {
        guard !isExporting else { return }
        isExporting = true
        outputStatus = nil
        exportIssue = nil

        Task {
            let pngData = await renderExport()
            self.isExporting = false

            guard let data = pngData else { return }

            if OutputService.shared.copyToClipboard(pngData: data) {
                if closeOnSuccess {
                    // Return is the one-key exit: the copy has landed, so close.
                    self.onClose()
                    return
                }
                // Cmd+C and the button keep the editor open (Discard is the explicit exit path)
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

/// An icon button in an editor bar: `ink-muted`, `ink-faint` when it cannot act.
struct EditorIconButton: View {
    let symbol: String
    let help: String
    let disabled: Bool
    let action: () -> Void

    init(_ symbol: String, help: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Quiet.Font.ui)
                .foregroundStyle(disabled ? Quiet.inkFaint : Quiet.inkMuted)
                .frame(width: Quiet.Space.s8, height: Quiet.Space.s8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The annotation tools, colours and line widths, shared by the image and video editors.
/// Selection is neutral: `selection` behind, `ink` in front, an `ink` ring round the colour.
/// The annotation colours are the picture's colours, not the interface's.
struct AnnotationStyleBar: View {
    @Binding var activeTool: AnnotationTool
    @Binding var color: CodableColor
    @Binding var width: CGFloat
    /// The image editor has a key for each tool; the video editor does not.
    var showsToolKeys: Bool

    static let colours: [CodableColor] = [.red, .green, .blue, .yellow, .orange, .white, .black]
    static let widths: [CGFloat] = [2.0, 4.0, 6.0, 8.0]

    var body: some View {
        HStack(spacing: Quiet.Space.s3) {
            HStack(spacing: Quiet.Space.s1) {
                ForEach(AnnotationTool.allCases) { tool in
                    let isActive = activeTool == tool
                    let name = showsToolKeys ? tool.tooltip : tool.rawValue
                    Button {
                        activeTool = tool
                    } label: {
                        Image(systemName: tool.systemImage)
                            .font(Quiet.Font.ui)
                            .foregroundStyle(isActive ? Quiet.ink : Quiet.inkMuted)
                            .frame(width: Quiet.Space.s8, height: Quiet.Space.s8)
                            .background(
                                RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous)
                                    .fill(isActive ? Quiet.selection : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(name)
                    .accessibilityLabel(name)
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }

            QuietRule(vertical: true)

            HStack(spacing: Quiet.Space.s2) {
                ForEach(Self.colours.indices, id: \.self) { index in
                    let colour = Self.colours[index]
                    let isSelected = color == colour
                    Button {
                        color = colour
                    } label: {
                        Circle()
                            .fill(colour.swiftUIColor)
                            .frame(width: Quiet.Space.s4, height: Quiet.Space.s4)
                            .overlay(Circle().strokeBorder(Quiet.line, lineWidth: 1))
                            .padding(Quiet.Space.s1)
                            .overlay(Circle().strokeBorder(isSelected ? Quiet.ink : Color.clear, lineWidth: 2))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(Self.colourName(colour))
                    .accessibilityLabel(Self.colourName(colour))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            QuietRule(vertical: true)

            HStack(spacing: Quiet.Space.s1) {
                ForEach(Self.widths, id: \.self) { lineWidth in
                    let isSelected = width == lineWidth
                    Button {
                        width = lineWidth
                    } label: {
                        Circle()
                            .fill(Quiet.ink)
                            .frame(width: lineWidth * 1.5 + 4, height: lineWidth * 1.5 + 4)
                            .frame(width: Quiet.Space.s6, height: Quiet.Space.s6)
                            .background(
                                RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous)
                                    .fill(isSelected ? Quiet.selection : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Line width \(Int(lineWidth))")
                    .accessibilityLabel("Line width \(Int(lineWidth))")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    static func colourName(_ colour: CodableColor) -> String {
        switch colour {
        case .red: return "Red"
        case .green: return "Green"
        case .blue: return "Blue"
        case .yellow: return "Yellow"
        case .orange: return "Orange"
        case .white: return "White"
        case .black: return "Black"
        default: return "Colour"
        }
    }
}
