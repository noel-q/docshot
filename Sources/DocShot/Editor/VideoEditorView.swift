import SwiftUI
import AppKit

public struct VideoEditorView: View {
    /// Redraws this view when the colour theme changes (C0.7).
    @ObservedObject private var themeController = ThemeController.shared
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
            // Top bar in Quiet: Back and what the recording is on the left; the result,
            // Discard and the one accent button, Save, on the right, each with its key.
            HStack(spacing: Quiet.Space.s3) {
                Button {
                    if viewModel.hasUnsavedChanges {
                        showReturnAlert = true
                    } else {
                        onExit(.returnToOutputChoice)
                    }
                } label: {
                    HStack(spacing: Quiet.Space.s1) {
                        KeyHint(keys: "esc")
                        Text("Back").font(Quiet.Font.ui).foregroundStyle(Quiet.inkMuted)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isExporting)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Back to the choices (esc)")
                .accessibilityLabel("Back")

                QuietRule(vertical: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit recording")
                        .font(Quiet.Font.ui)
                        .foregroundStyle(Quiet.ink)
                    Text(verbatim: "\(formatDuration(viewModel.timelineDuration)) · \(Int(viewModel.project.sourcePixelSize.width)) × \(Int(viewModel.project.sourcePixelSize.height)) px · \(viewModel.project.hasSourceAudio ? "With sound" : "No sound")")
                        .font(Quiet.Font.caption.monospacedDigit())
                        .foregroundStyle(Quiet.inkMuted)
                }

                Spacer(minLength: Quiet.Space.s2)

                if viewModel.isExporting {
                    HStack(spacing: Quiet.Space.s2) {
                        ProgressView()
                            .controlSize(.small)
                        Text(viewModel.statusMessage ?? "Saving the edited MP4…")
                            .font(Quiet.Font.caption)
                            .foregroundStyle(Quiet.inkMuted)
                    }
                } else if let error = viewModel.exportError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(Quiet.Font.caption)
                        .foregroundStyle(Quiet.danger)
                        .lineLimit(2)
                } else if let status = viewModel.statusMessage {
                    Text(status)
                        .font(Quiet.Font.caption)
                        .foregroundStyle(Quiet.inkMuted)
                }

                Button("Discard…") {
                    showDiscardAlert = true
                }
                .controlSize(.large)
                .disabled(viewModel.isExporting)
                .help("Discard the recording")

                Button {
                    performSave()
                } label: {
                    AccentButtonLabel("Save MP4…  ⌘S")
                }
                .buttonStyle(.borderedProminent)
                .tint(Quiet.accent)
                .controlSize(.large)
                .disabled(viewModel.isExporting)
                .keyboardShortcut("s", modifiers: [.command])
                .help("Save the edited MP4 (⌘S)")
                .accessibilityLabel("Save MP4")
            }
            .padding(.horizontal, Quiet.Space.s4)
            .padding(.vertical, Quiet.Space.s3)
            .background(Quiet.surface)

            QuietRule()

            VideoAnnotationToolbar(viewModel: viewModel)

            QuietRule()

            // AVPlayer Preview with Canvas Overlay
            VideoPlayerPreviewView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            QuietRule()

            // Timeline & Segment Inspector Panel
            VideoTimelineView(viewModel: viewModel)
        }
        .frame(minWidth: 960, minHeight: 650)
        // Behind the see-through rules, so they blend as `line` should.
        .background(Quiet.surface)
        .alert(isPresented: $showDiscardAlert) {
            Alert(
                title: Text("Discard the recording?"),
                message: Text("It has not been saved, so discarding deletes it."),
                primaryButton: .destructive(Text("Discard")) {
                    onExit(.discardRecording)
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showReturnAlert) {
            Alert(
                title: Text("Discard your edits?"),
                message: Text("The original recording is kept. You can save it, export a GIF or discard it from the choices."),
                primaryButton: .destructive(Text("Discard edits")) {
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
