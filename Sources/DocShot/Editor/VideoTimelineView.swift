import SwiftUI
import AppKit

public struct VideoTimelineView: View {
    /// Redraws this view when the colour theme changes (C0.7).
    @ObservedObject private var themeController = ThemeController.shared
    @ObservedObject var viewModel: VideoEditorViewModel

    public init(viewModel: VideoEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: Quiet.Space.s3) {
            // Transport and scrubber. Neutral: the accent stays for Save.
            HStack(spacing: Quiet.Space.s3) {
                HStack(spacing: Quiet.Space.s1) {
                    EditorIconButton("backward.end", help: "Go to the start") { viewModel.seek(to: 0) }
                    EditorIconButton("gobackward", help: "Back one second") { viewModel.stepFrame(by: -1.0) }
                    Button {
                        viewModel.togglePlayPause()
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(Quiet.Font.ui)
                            .foregroundStyle(Quiet.ink)
                            .frame(width: Quiet.Space.s8, height: Quiet.Space.s8)
                            .background(Circle().fill(Quiet.selection))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.space, modifiers: [])
                    .help(viewModel.isPlaying ? "Pause (Space)" : "Play (Space)")
                    .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
                    EditorIconButton("goforward", help: "Forward one second") { viewModel.stepFrame(by: 1.0) }
                    EditorIconButton("forward.end", help: "Go to the end") { viewModel.seek(to: viewModel.timelineDuration) }
                }

                Text("\(formatTime(viewModel.currentTimelineTime)) / \(formatTime(viewModel.timelineDuration))")
                    .font(Quiet.Font.caption.monospacedDigit())
                    .foregroundStyle(Quiet.ink)
                    .fixedSize()

                Slider(
                    value: Binding(
                        get: { viewModel.currentTimelineTime },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...max(0.01, viewModel.timelineDuration)
                )
                .tint(Quiet.inkMuted)
                .accessibilityLabel("Playhead")
            }
            .padding(.horizontal, Quiet.Space.s4)
            .padding(.top, Quiet.Space.s3)

            QuietRule()

            HStack(alignment: .top, spacing: Quiet.Space.s4) {
                VStack(alignment: .leading, spacing: Quiet.Space.s2) {
                    Text("Clips (\(viewModel.project.segments.count))")
                        .font(Quiet.Font.label)
                        .foregroundStyle(Quiet.inkMuted)

                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: Quiet.Space.s2) {
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
                        .padding(.vertical, Quiet.Space.s1)
                    }
                }
                .frame(maxWidth: .infinity)

                QuietRule(vertical: true)
                    .frame(height: 100)

                VStack(alignment: .leading, spacing: Quiet.Space.s2) {
                    if let segment = viewModel.selectedSegment {
                        Text("Trim clip \(segmentIndex(for: segment.id) + 1)")
                            .font(Quiet.Font.label)
                            .foregroundStyle(Quiet.inkMuted)

                        HStack(spacing: Quiet.Space.s3) {
                            trimControl(title: "Start", time: segment.sourceRange.start) {
                                if let (seg, localTime) = viewModel.currentSegmentAndLocalTime, seg.id == segment.id {
                                    let newStart = segment.sourceRange.start + localTime
                                    if newStart < segment.sourceRange.end - VideoTimeRange.minimumDuration {
                                        viewModel.trimSegment(id: segment.id, startInSource: newStart, endInSource: segment.sourceRange.end)
                                    }
                                }
                            }
                            trimControl(title: "End", time: segment.sourceRange.end) {
                                if let (seg, localTime) = viewModel.currentSegmentAndLocalTime, seg.id == segment.id {
                                    let newEnd = segment.sourceRange.start + localTime
                                    if newEnd > segment.sourceRange.start + VideoTimeRange.minimumDuration {
                                        viewModel.trimSegment(id: segment.id, startInSource: segment.sourceRange.start, endInSource: newEnd)
                                    }
                                }
                            }
                        }

                        let annotations = viewModel.project.annotations(forSegmentID: segment.id)
                        if !annotations.isEmpty {
                            Text("Marks (\(annotations.count))")
                                .font(Quiet.Font.label)
                                .foregroundStyle(Quiet.inkMuted)
                                .padding(.top, Quiet.Space.s1)

                            ForEach(annotations) { annotation in
                                HStack(spacing: Quiet.Space.s2) {
                                    Circle()
                                        .fill(annotation.item.color.swiftUIColor)
                                        .frame(width: Quiet.Space.s2, height: Quiet.Space.s2)
                                    Text("\(annotation.item.typeDescription), \(formatTime(annotation.sourceRange.start)) to \(formatTime(annotation.sourceRange.end))")
                                        .font(Quiet.Font.caption.monospacedDigit())
                                        .foregroundStyle(Quiet.ink)
                                    Spacer(minLength: 0)
                                    EditorIconButton("xmark", help: "Remove this mark") {
                                        viewModel.removeAnnotation(id: annotation.id)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Choose a clip to trim it.")
                            .font(Quiet.Font.caption)
                            .foregroundStyle(Quiet.inkMuted)
                    }
                }
                .frame(width: 280, alignment: .leading)
            }
            .padding(.horizontal, Quiet.Space.s4)
            .padding(.bottom, Quiet.Space.s3)
        }
        .background(Quiet.surface)
    }

    /// One end of the trim: its time and a button that moves it to the playhead.
    private func trimControl(title: String, time: TimeInterval, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Quiet.Space.s1) {
            Text(title)
                .font(Quiet.Font.caption)
                .foregroundStyle(Quiet.inkMuted)
            HStack(spacing: Quiet.Space.s1) {
                Text(formatTime(time))
                    .font(Quiet.Font.caption.monospacedDigit())
                    .foregroundStyle(Quiet.ink)
                Button("To playhead", action: action)
                    .controlSize(.small)
                    .help("Move the \(title.lowercased()) to the playhead")
            }
        }
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
    /// Redraws this view when the colour theme changes (C0.7).
    @ObservedObject var themeController = ThemeController.shared
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
        VStack(alignment: .leading, spacing: Quiet.Space.s1) {
            HStack {
                Text("Clip \(index + 1)")
                    .font(Quiet.Font.label)
                    .foregroundStyle(Quiet.ink)
                Spacer(minLength: 0)
                if isPlayheadHere {
                    Circle()
                        .fill(Quiet.ink)
                        .frame(width: Quiet.Space.s2, height: Quiet.Space.s2)
                        .help("The playhead is in this clip")
                        .accessibilityLabel("Playhead here")
                }
            }

            Text("\(String(format: "%.1f", segment.sourceRange.start)) to \(String(format: "%.1f", segment.sourceRange.end)) s")
                .font(Quiet.Font.caption.monospacedDigit())
                .foregroundStyle(Quiet.inkMuted)

            HStack(spacing: 0) {
                EditorIconButton("chevron.left", help: "Move earlier", disabled: index == 0, action: onMoveLeft)
                EditorIconButton("chevron.right", help: "Move later", disabled: index == totalSegments - 1, action: onMoveRight)
                Spacer(minLength: 0)
                EditorIconButton("trash", help: "Delete this clip", disabled: totalSegments <= 1, action: onDelete)
            }
        }
        .padding(Quiet.Space.s2)
        .frame(width: 150)
        .background(
            RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous)
                .fill(isSelected ? Quiet.selection : Quiet.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous)
                .strokeBorder(isSelected ? Quiet.ink : Quiet.line, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clip \(index + 1), \(String(format: "%.1f", segment.duration)) seconds")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
