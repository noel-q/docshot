import AppKit
import SwiftUI

/// A compact, app-owned recording control surface. Window recordings are desktop-independent and
/// region recordings explicitly exclude DocShot, so this panel is absent from recorded pixels.
@MainActor
final class RecordingStatusPanelController {
    private let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 270, height: 86),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
    }

    func show(coordinator: RecordingCoordinator) {
        panel.contentView = NSHostingView(rootView: RecordingStatusPanelView(coordinator: coordinator))
        positionPanel()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - panel.frame.width - 18,
            y: frame.maxY - panel.frame.height - 18
        ))
    }
}

private struct RecordingStatusPanelView: View {
    @ObservedObject var coordinator: RecordingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(indicatorColor).frame(width: 9, height: 9)
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                if case .recording(_, let startedAt) = coordinator.state {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(RecordingCoordinator.durationText(context.date.timeIntervalSince(startedAt)))
                            .monospacedDigit()
                            .font(.system(size: 13, weight: .medium))
                    }
                }
            }

            HStack {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if canStop {
                    Button("Stop") { coordinator.stopRecording() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(width: 270, height: 86)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var canStop: Bool {
        if case .starting = coordinator.state { return true }
        if case .recording = coordinator.state { return true }
        return false
    }

    private var title: String {
        switch coordinator.state {
        case .starting: "Starting recording"
        case .recording: "Recording"
        case .stopping: "Stopping recording"
        case .awaitingOutput: "Recording finished"
        default: "Recording"
        }
    }

    private var detail: String {
        switch coordinator.state {
        case .starting: "Preparing the selected target"
        case .recording: "Video only · MP4"
        case .stopping: "Finalising the MP4"
        case .awaitingOutput: "Choose Save or Discard in the dialog"
        default: ""
        }
    }

    private var indicatorColor: Color {
        switch coordinator.state {
        case .recording: .red
        case .stopping: .orange
        default: .secondary
        }
    }
}
