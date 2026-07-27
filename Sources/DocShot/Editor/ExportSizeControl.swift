import SwiftUI
import AppKit

/// Compact export-size selector for the editor action bar. Shows the dimensions the next
/// Copy/Save will produce, with presets and a custom width/height popover.
public struct ExportSizeControl: View {
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
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                Text(viewModel.resolvedExportSizeLabel ?? "Invalid size")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(viewModel.exportSizeErrorMessage == nil ? .primary : .red)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(DesignTokens.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(DesignTokens.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.borderAdaptive, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Output size for Copy and Save")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            popoverContent
        }
        .onAppear(perform: syncFieldsFromResolvedSize)
        .onChange(of: isPopoverPresented) { _, presented in
            if presented { syncFieldsFromResolvedSize() }
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Size")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignTokens.secondaryText)

            HStack(spacing: 6) {
                ForEach(presets, id: \.label) { preset in
                    Button(preset.label) {
                        viewModel.exportSize = preset.size
                        syncFieldsFromResolvedSize()
                    }
                    .buttonStyle(.bordered)
                    .tint(viewModel.exportSize == preset.size ? DesignTokens.primaryAccent : nil)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Custom")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DesignTokens.secondaryText)

                HStack(spacing: 8) {
                    TextField("Width", text: $widthField)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 78)
                        .onChange(of: widthField) { _, _ in applyCustomSize(changedEdge: .width) }

                    Text("×")
                        .foregroundColor(DesignTokens.secondaryText)

                    TextField("Height", text: $heightField)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 78)
                        .onChange(of: heightField) { _, _ in applyCustomSize(changedEdge: .height) }

                    Text("px")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.secondaryText)
                }

                Toggle("Lock aspect ratio", isOn: $aspectLocked)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }

            Divider()

            if let error = viewModel.exportSizeErrorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let label = viewModel.resolvedExportSizeLabel {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copy and Save will output \(label) px")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.secondaryText)
                    if isUpscaling {
                        Text("Enlarging past native size will look softer.")
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 290)
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
