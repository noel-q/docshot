import SwiftUI
import AppKit

public struct VideoAnnotationToolbar: View {
    @ObservedObject var viewModel: VideoEditorViewModel

    private let availableColors: [CodableColor] = [
        .red, .green, .blue, .yellow, .orange, .white, .black
    ]
    private let availableWidths: [CGFloat] = [2.0, 4.0, 6.0, 8.0]

    public init(viewModel: VideoEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Annotation Tool Selector
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

            // Color Presets
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

            // Stroke Width Selector
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

            // Split Action & Undo / Redo / Delete
            HStack(spacing: 8) {
                Button(action: {
                    viewModel.splitAtPlayhead()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "scissors")
                        Text("Split")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignTokens.primaryAccent)
                }
                .keyboardShortcut("k", modifiers: [.command])
                .help("Split clip at playhead (⌘K)")

                Divider()
                    .frame(height: 18)

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

                Button(action: {
                    if let selectedID = viewModel.selectedAnnotationID {
                        viewModel.removeAnnotation(id: selectedID)
                    }
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .disabled(viewModel.selectedAnnotationID == nil)
                .keyboardShortcut(.delete, modifiers: [])
                .help("Delete Selection")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DesignTokens.windowBackground)
    }
}
