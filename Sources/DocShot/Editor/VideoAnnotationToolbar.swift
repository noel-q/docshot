import SwiftUI
import AppKit

/// The video editor's drawing bar in Quiet: the shared tools, colours and widths, then Split,
/// undo, redo and delete, each with its key. Neutral throughout; the accent stays for Save.
public struct VideoAnnotationToolbar: View {
    @ObservedObject private var themeController = ThemeController.shared
    @ObservedObject var viewModel: VideoEditorViewModel

    public init(viewModel: VideoEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: Quiet.Space.s3) {
            AnnotationStyleBar(
                activeTool: $viewModel.activeTool,
                color: $viewModel.selectedColor,
                width: $viewModel.selectedStrokeWidth,
                showsToolKeys: false
            )

            Spacer(minLength: 0)

            Button {
                viewModel.splitAtPlayhead()
            } label: {
                Label("Split  ⌘K", systemImage: "scissors")
                    .font(Quiet.Font.ui)
                    .fixedSize()
            }
            .layoutPriority(1)
            .keyboardShortcut("k", modifiers: [.command])
            .help("Split the clip at the playhead (⌘K)")
            .accessibilityLabel("Split")

            QuietRule(vertical: true)

            HStack(spacing: Quiet.Space.s1) {
                EditorIconButton("arrow.uturn.backward", help: "Undo (⌘Z)", disabled: !viewModel.canUndo) { viewModel.undo() }
                    .keyboardShortcut("z", modifiers: [.command])
                EditorIconButton("arrow.uturn.forward", help: "Redo (⇧⌘Z)", disabled: !viewModel.canRedo) { viewModel.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                EditorIconButton("trash", help: "Delete the selected mark (⌫)", disabled: viewModel.selectedAnnotationID == nil) {
                    if let selectedID = viewModel.selectedAnnotationID {
                        viewModel.removeAnnotation(id: selectedID)
                    }
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
        }
        .padding(.horizontal, Quiet.Space.s4)
        .padding(.vertical, Quiet.Space.s2)
        .background(Quiet.surface)
    }
}
