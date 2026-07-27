import SwiftUI
import AppKit

public struct VideoEditorView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    public var onExit: (VideoEditorExit) -> Void

    @State private var showDiscardAlert: Bool = false
    @State private var showReturnAlert: Bool = false

    public init(viewModel: VideoEditorViewModel, onExit: @escaping (VideoEditorExit) -> Void) {
        self.viewModel = viewModel
        self.onExit = onExit
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Window Action Bar
            HStack(spacing: 16) {
                // Back / Cancel Button
                Button(action: {
                    if viewModel.hasUnsavedChanges {
                        showReturnAlert = true
                    } else {
                        onExit(.returnToOutputChoice)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DesignTokens.secondaryText)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isExporting)
                .keyboardShortcut(.escape, modifiers: [])

                Divider()
                    .frame(height: 18)

                // Recording Specs Readout
                VStack(alignment: .leading, spacing: 2) {
                    Text("DocShot Video Editor")
                        .font(.system(size: 13, weight: .bold))
                    Text("\(formatDuration(viewModel.timelineDuration)) · \(Int(viewModel.project.sourcePixelSize.width)) × \(Int(viewModel.project.sourcePixelSize.height)) px · \(viewModel.project.hasSourceAudio ? "Audio On" : "No Audio")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignTokens.secondaryText)
                }

                Spacer()

                // Status & Export Indicator
                if viewModel.isExporting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(viewModel.statusMessage ?? "Exporting edited MP4...")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DesignTokens.primaryAccent)
                    }
                } else if let error = viewModel.exportError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                    }
                } else if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.secondaryText)
                }

                // Discard Button
                Button(action: {
                    showDiscardAlert = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                        Text("Discard")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DesignTokens.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isExporting)

                // Save Edited MP4 Button
                Button(action: {
                    performSave()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("Save Edited MP4…")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(viewModel.isExporting ? Color.gray : DesignTokens.primaryAccent)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isExporting)
                .keyboardShortcut("s", modifiers: [.command])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(DesignTokens.windowBackground)

            Divider()

            // Annotation Toolbar
            VideoAnnotationToolbar(viewModel: viewModel)

            Divider()

            // AVPlayer Preview with Canvas Overlay
            VideoPlayerPreviewView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Timeline & Segment Inspector Panel
            VideoTimelineView(viewModel: viewModel)
        }
        .frame(minWidth: 850, minHeight: 650)
        .background(DesignTokens.windowBackground)
        .alert(isPresented: $showDiscardAlert) {
            Alert(
                title: Text("Discard Changes?"),
                message: Text("Discarding deletes this recording because it has not been saved."),
                primaryButton: .destructive(Text("Discard")) {
                    onExit(.discardRecording)
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showReturnAlert) {
            Alert(
                title: Text("Discard Edits?"),
                message: Text("Your original recording will be kept. You can save it, export a GIF, or discard it from the output choices."),
                primaryButton: .destructive(Text("Return to Output Choices")) {
                    onExit(.returnToOutputChoice)
                },
                secondaryButton: .cancel()
            )
        }
        .onChange(of: viewModel.isClosed) { _, closed in
            if closed, viewModel.saveCompletedURL != nil {
                onExit(.savedOutput)
            }
        }
    }

    private func performSave() {
        let parentWin = VideoEditorWindowController.shared.currentWindow
        viewModel.saveEditedMP4(parentWindow: parentWin)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
