import SwiftUI

/// The building blocks of Settings in Quiet (pilot step 3; Quiet `Toggle` and `patterns.md`):
/// a page on `canvas`, groups under short titles, one `surface` panel per group with inset
/// `line` dividers between rows, and rows of a title, at most one line of `ink-muted`, and a
/// control on the right.

/// One Settings tab: a fixed-width column of groups on the window canvas.
/// The tallest a page may be where it is shown (the compact Settings panel lowers it on a
/// short screen so the page scrolls instead of the panel running off the screen).
private struct SettingsPageMaxHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 640
}

extension EnvironmentValues {
    var settingsPageMaxHeight: CGFloat {
        get { self[SettingsPageMaxHeightKey.self] }
        set { self[SettingsPageMaxHeightKey.self] = newValue }
    }
}

struct SettingsPage<Content: View>: View {
    @ObservedObject var themeController = ThemeController.shared
    @Environment(\.settingsPageMaxHeight) private var maxHeight
    var width: CGFloat = 560
    @ViewBuilder let content: Content

    static var width: CGFloat { 560 }
    /// The tallest a tab gets before it scrolls: a 13-inch display has about 800 points of
    /// usable height, and the title bar and toolbar take about 80.
    static var maxHeight: CGFloat { 640 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Quiet.Space.s6) {
                content
            }
            .padding(Quiet.Space.s6)
            .frame(width: width, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The page's ideal height is its content's, up to the cap, known at once (no measuring
        // after drawing), so the window can size itself before the tab appears.
        .frame(width: width)
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(Quiet.canvas)
        // No page-wide tint: only switches take the accent (one accent per view); buttons and
        // the segmented control stay neutral.
    }
}

/// A titled group: one panel holding its rows, and an optional note under it.
struct SettingsGroup<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Quiet.Space.s2) {
            Text(title)
                .font(Quiet.Font.headline)
                .foregroundStyle(Quiet.ink)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: Quiet.Radius.md, style: .continuous).fill(Quiet.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Quiet.Radius.md, style: .continuous).stroke(Quiet.line, lineWidth: 1)
            )
            if let note {
                Text(note)
                    .font(Quiet.Font.caption)
                    .foregroundStyle(Quiet.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Quiet.Space.s1)
            }
        }
    }
}

/// The inset line between two rows of a panel.
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Quiet.line)
            .frame(height: 1)
            .padding(.leading, Quiet.Space.s4)
    }
}

/// A row: title, optional one line of detail, and a control on the right.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var detail: String?
    var detailIsError = false
    /// A path or similar: one line, shortened in the middle.
    var detailIsPath = false
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: Quiet.Space.s4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Quiet.Font.ui)
                    .foregroundStyle(Quiet.ink)
                if let detail {
                    if detailIsError {
                        Label(detail, systemImage: "exclamationmark.triangle")
                            .font(Quiet.Font.caption)
                            .foregroundStyle(Quiet.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if detailIsPath {
                        Text(detail)
                            .font(Quiet.Font.caption)
                            .foregroundStyle(Quiet.inkMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(detail)
                            .font(Quiet.Font.caption)
                            .foregroundStyle(Quiet.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .padding(.horizontal, Quiet.Space.s4)
        .padding(.vertical, Quiet.Space.s3)
        .accessibilityElement(children: .contain)
    }
}

/// A row whose control is a switch (Quiet `Toggle`: native switch tinted with the accent).
struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    var detailIsError = false
    /// The switch's spoken name when the title alone is ambiguous.
    var accessibilityName: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail, detailIsError: detailIsError) {
            Toggle(accessibilityName ?? title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(Quiet.accent)
        }
    }
}

/// A row whose control is a menu of fixed choices.
struct SettingsPickerRow<Value: Hashable, Options: View>: View {
    let title: String
    var detail: String?
    @Binding var selection: Value
    @ViewBuilder let options: Options

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Picker(title, selection: $selection) {
                options
            }
            .labelsHidden()
            .pickerStyle(.menu)
            // A set width: a menu that lists its choices with ForEach has no ideal width, so
            // fixedSize would collapse it.
            .frame(width: 180)
        }
    }
}
