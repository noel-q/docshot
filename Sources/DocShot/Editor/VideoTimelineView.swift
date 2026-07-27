import SwiftUI
import AppKit

public struct VideoTimelineView: View {
    @ObservedObject var viewModel: VideoEditorViewModel

    public init(viewModel: VideoEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Playback Transport Controls & Scrubber
            HStack(spacing: 12) {
                // Play/Pause & Step Buttons
                HStack(spacing: 6) {
                    Button(action: { viewModel.seek(to: 0) }) {
                        Image(systemName: "gobackward.10")
                    }
                    .buttonStyle(.plain)
                    .help("Jump to start")

                    Button(action: { viewModel.stepFrame(by: -1.0) }) {
                        Image(systemName: "backward.frame")
                    }
                    .buttonStyle(.plain)
                    .help("Step back 1 second")

                    Button(action: { viewModel.togglePlayPause() }) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(DesignTokens.primaryAccent)
                            .frame(width: 28, height: 28)
                            .background(DesignTokens.primaryAccent.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.space, modifiers: [])
                    .help("Play/Pause (Space)")

                    Button(action: { viewModel.stepFrame(by: 1.0) }) {
                        Image(systemName: "forward.frame")
                    }
                    .buttonStyle(.plain)
                    .help("Step forward 1 second")

                    Button(action: { viewModel.seek(to: viewModel.timelineDuration) }) {
                        Image(systemName: "goforward.10")
                    }
                    .buttonStyle(.plain)
                    .help("Jump to end")
                }

                // Monospaced Timestamp Readout
                Text("\(formatTime(viewModel.currentTimelineTime)) / \(formatTime(viewModel.timelineDuration))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(width: 130)

                // Timeline Scrubber Slider
                Slider(
                    value: Binding(
                        get: { viewModel.currentTimelineTime },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...max(0.01, viewModel.timelineDuration)
                )
                .tint(DesignTokens.primaryAccent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Divider()

            // Segment Timeline & Inspector
            HStack(alignment: .top, spacing: 16) {
                // Segment Timeline List
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Timeline Segments (\(viewModel.project.segments.count))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(DesignTokens.secondaryText)
                        Spacer()
                    }

                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 8) {
                            ForEach(Array(viewModel.project.segments.enumerated()), id: \.element.id) { index, segment in
                                SegmentCardView(
                                    segment: segment,
                                    index: index,
                                    totalSegments: viewModel.project.segments.count,
                                    isSelected: viewModel.selectedSegmentID == segment.id,
                                    isPlayheadHere: isPlayheadInSegment(segment),
                                    onSelect: {
                                        viewModel.selectedSegmentID = segment.id
                                    },
                                    onMoveLeft: {
                                        viewModel.moveSegment(id: segment.id, toIndex: max(0, index - 1))
                                    },
                                    onMoveRight: {
                                        viewModel.moveSegment(id: segment.id, toIndex: min(viewModel.project.segments.count - 1, index + 1))
                                    },
                                    onDelete: {
                                        viewModel.removeSegment(id: segment.id)
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 100)

                // Selected Segment Trim Controls & Annotation Inspector
                VStack(alignment: .leading, spacing: 8) {
                    if let segment = viewModel.selectedSegment {
                        Text("Trim Segment #\(segmentIndex(for: segment.id) + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(DesignTokens.secondaryText)

                        HStack(spacing: 12) {
                            // Trim In Control
                            VStack(alignment: .leading, spacing: 2) {
                                Text("In Point")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(DesignTokens.secondaryText)
                                HStack(spacing: 4) {
                                    Text(formatTime(segment.sourceRange.start))
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    Button("Set Playhead") {
                                        if let (seg, localTime) = viewModel.currentSegmentAndLocalTime, seg.id == segment.id {
                                            let newStart = segment.sourceRange.start + localTime
                                            if newStart < segment.sourceRange.end - VideoTimeRange.minimumDuration {
                                                viewModel.trimSegment(id: segment.id, startInSource: newStart, endInSource: segment.sourceRange.end)
                                            }
                                        }
                                    }
                                    .font(.system(size: 10))
                                    .buttonStyle(.bordered)
                                }
                            }

                            // Trim Out Control
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Out Point")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(DesignTokens.secondaryText)
                                HStack(spacing: 4) {
                                    Text(formatTime(segment.sourceRange.end))
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    Button("Set Playhead") {
                                        if let (seg, localTime) = viewModel.currentSegmentAndLocalTime, seg.id == segment.id {
                                            let newEnd = segment.sourceRange.start + localTime
                                            if newEnd > segment.sourceRange.start + VideoTimeRange.minimumDuration {
                                                viewModel.trimSegment(id: segment.id, startInSource: segment.sourceRange.start, endInSource: newEnd)
                                            }
                                        }
                                    }
                                    .font(.system(size: 10))
                                    .buttonStyle(.bordered)
                                }
                            }
                        }

                        // Annotations List on Segment
                        let annotations = viewModel.project.annotations(forSegmentID: segment.id)
                        if !annotations.isEmpty {
                            Text("Annotations (\(annotations.count))")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(DesignTokens.secondaryText)
                                .padding(.top, 4)

                            ForEach(annotations) { annotation in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(annotation.item.color.swiftUIColor)
                                        .frame(width: 8, height: 8)
                                    Text("\(annotation.item.typeDescription) [\(formatTime(annotation.sourceRange.start)) - \(formatTime(annotation.sourceRange.end))]")
                                        .font(.system(size: 10, design: .monospaced))
                                    Spacer()
                                    Button(action: {
                                        viewModel.removeAnnotation(id: annotation.id)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        Text("Select a segment to trim")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignTokens.secondaryText)
                    }
                }
                .frame(width: 280)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(DesignTokens.cardBackground)
    }

    private func isPlayheadInSegment(_ segment: VideoSegment) -> Bool {
        guard let (currentSeg, _) = viewModel.currentSegmentAndLocalTime else { return false }
        return currentSeg.id == segment.id
    }

    private func segmentIndex(for id: UUID) -> Int {
        viewModel.project.segments.firstIndex(where: { $0.id == id }) ?? 0
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let mins = total / 60
        let secs = total % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", mins, secs, millis)
    }
}

// MARK: - Segment Card View

private struct SegmentCardView: View {
    let segment: VideoSegment
    let index: Int
    let totalSegments: Int
    let isSelected: Bool
    let isPlayheadHere: Bool
    let onSelect: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Segment #\(index + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isSelected ? DesignTokens.primaryAccent : .primary)
                Spacer()
                if isPlayheadHere {
                    Circle()
                        .fill(DesignTokens.identityAccent)
                        .frame(width: 6, height: 6)
                }
            }

            Text("Src: \(String(format: "%.1f", segment.sourceRange.start))s - \(String(format: "%.1f", segment.sourceRange.end))s")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(DesignTokens.secondaryText)

            Text("Duration: \(String(format: "%.1f", segment.duration))s")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                Button(action: onMoveLeft) {
                    Image(systemName: "chevron.left")
                }
                .disabled(index == 0)

                Button(action: onMoveRight) {
                    Image(systemName: "chevron.right")
                }
                .disabled(index == totalSegments - 1)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .disabled(totalSegments <= 1)
            }
            .font(.system(size: 10))
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
        .padding(8)
        .frame(width: 140)
        .background(isSelected ? DesignTokens.primaryAccent.opacity(0.1) : DesignTokens.graphiteBase)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? DesignTokens.primaryAccent : DesignTokens.borderSubtle, lineWidth: isSelected ? 2 : 1)
        )
        .onTapGesture {
            onSelect()
        }
    }
}
