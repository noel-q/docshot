import SwiftUI
import AppKit

/// Compact export-size selector for the editor action bar. Shows the dimensions the next
/// Copy/Save will produce, with presets and a custom width/height popover.
public struct ExportSizeControl: View {
    /// Redraws this view when the colour theme changes (C0.7).
    @ObservedObject private var themeController = ThemeController.shared
    @ObservedObject var viewModel: EditorViewModel

    @State private var isPopoverPresented = false
    @State private var widthField: String = ""
    @State private var heightField: String = ""
    @State private var aspectLocked = true

    public init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
    }

    private let presets: [(label: String, size: ExportSize)] = [
        ("Native", .native),
        ("50%", .percent(50)),
        ("200%", .percent(200))
    ]

    public var body: some View {
        Button(action: { isPopoverPresented.toggle() }) {
            HStack(spacing: Quiet.Space.s1) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(Quiet.Font.caption)
                    .foregroundStyle(Quiet.inkMuted)
                Text(viewModel.resolvedExportSizeLabel.map { "\($0) px" } ?? "Size not valid")
                    .font(Quiet.Font.caption.monospacedDigit())
                    .foregroundStyle(viewModel.exportSizeErrorMessage == nil ? Quiet.ink : Quiet.danger)
                Image(systemName: "chevron.up.chevron.down")
                    .font(Quiet.Font.caption)
                    .foregroundStyle(Quiet.inkMuted)
            }
            .padding(.horizontal, Quiet.Space.s2)
            .padding(.vertical, Quiet.Space.s1)
            .background(RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous).fill(Quiet.controlSurface))
            .overlay(RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous).stroke(Quiet.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("The size Copy and Save make")
        .accessibilityLabel("Output size, \(viewModel.resolvedExportSizeLabel ?? "not valid")")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            popoverContent
        }
        .onAppear(perform: syncFieldsFromResolvedSize)
        .onChange(of: isPopoverPresented) { _, presented in
            if presented { syncFieldsFromResolvedSize() }
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: Quiet.Space.s3) {
            Text("Output size")
                .font(Quiet.Font.label)
                .foregroundStyle(Quiet.inkMuted)

            // Neutral selection: the chosen size is filled in `ink-muted`, never the accent.
            HStack(spacing: Quiet.Space.s1) {
                ForEach(presets, id: \.label) { preset in
                    if viewModel.exportSize == preset.size {
                        Button(preset.label) {}
                            .buttonStyle(.borderedProminent)
                            .tint(Quiet.inkMuted)
                            .accessibilityAddTraits(.isSelected)
                    } else {
                        Button(preset.label) {
                            viewModel.exportSize = preset.size
                            syncFieldsFromResolvedSize()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            QuietRule()

            VStack(alignment: .leading, spacing: Quiet.Space.s2) {
                Text("Custom")
                    .font(Quiet.Font.label)
                    .foregroundStyle(Quiet.inkMuted)

                HStack(spacing: 8) {
                    TextField("Width", text: $widthField)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 78)
                        .onChange(of: widthField) { _, _ in applyCustomSize(changedEdge: .width) }

                    Text("×")
                        .foregroundStyle(Quiet.inkMuted)

                    TextField("Height", text: $heightField)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 78)
                        .onChange(of: heightField) { _, _ in applyCustomSize(changedEdge: .height) }

                    Text("px")
                        .font(Quiet.Font.caption)
                        .foregroundStyle(Quiet.inkMuted)
                }

                Toggle("Lock aspect ratio", isOn: $aspectLocked)
                    .toggleStyle(.checkbox)
                    .font(Quiet.Font.caption)
            }

            QuietRule()

            if let error = viewModel.exportSizeErrorMessage {
                Text(error)
                    .font(Quiet.Font.caption)
                    .foregroundStyle(Quiet.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let label = viewModel.resolvedExportSizeLabel {
                VStack(alignment: .leading, spacing: Quiet.Space.s1) {
                    Text("Copy and Save make \(label) px.")
                        .font(Quiet.Font.caption)
                        .foregroundStyle(Quiet.inkMuted)
                    if isUpscaling {
                        Text("Larger than the original looks softer.")
                            .font(Quiet.Font.caption)
                            .foregroundStyle(Quiet.inkMuted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Quiet.Space.s4)
        .frame(width: 300)
    }

    private enum ChangedEdge { case width, height }

    private var nativeSize: CGSize {
        viewModel.flattenedPixelSize
    }

    private var isUpscaling: Bool {
        guard case .success(let size) = viewModel.resolvedExportSize else { return false }
        return size.width > nativeSize.width || size.height > nativeSize.height
    }

    /// Fills the custom fields with whatever the current selection resolves to, so switching
    /// to Custom starts from the visible dimensions rather than an empty box.
    private func syncFieldsFromResolvedSize() {
        guard case .success(let size) = viewModel.resolvedExportSize else { return }
        widthField = String(Int(size.width))
        heightField = String(Int(size.height))
    }

    private func applyCustomSize(changedEdge: ChangedEdge) {
        let width = Double(widthField) ?? 0
        let height = Double(heightField) ?? 0

        if aspectLocked {
            switch changedEdge {
            case .width:
                if let locked = ExportSize.aspectLockedHeight(forWidth: width, sourceSize: nativeSize) {
                    let lockedText = String(Int(locked))
                    if heightField != lockedText { heightField = lockedText }
                    viewModel.exportSize = .pixels(width: width, height: locked)
                    return
                }
            case .height:
                if let locked = ExportSize.aspectLockedWidth(forHeight: height, sourceSize: nativeSize) {
                    let lockedText = String(Int(locked))
                    if widthField != lockedText { widthField = lockedText }
                    viewModel.exportSize = .pixels(width: locked, height: height)
                    return
                }
            }
        }

        viewModel.exportSize = .pixels(width: width, height: height)
    }
}
