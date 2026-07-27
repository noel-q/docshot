import SwiftUI

/// The compact Record / Cancel control shown after a target is selected.
///
/// No stream exists while this is on screen. Recording begins only when Record is pressed, and
/// Cancel leaves no temporary file behind because none has been created yet.
struct RecordingConfirmationView: View {
    let sizeText: String
    let audioText: String
    let onRecord: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                Text(sizeText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }

            Text(audioText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.75))

            Divider()
                .frame(height: 16)
                .overlay(Color.white.opacity(0.25))

            Button(action: onRecord) {
                Text("Record")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .keyboardShortcut(.defaultAction)

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}
