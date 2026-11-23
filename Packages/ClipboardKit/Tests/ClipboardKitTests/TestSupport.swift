import Foundation
@testable import ClipboardKit

/// A fixed clock so ages are exact.
let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

func days(_ count: Double) -> TimeInterval { count * 24 * 60 * 60 }

/// An item with chosen size, age and pin state, for the pure rules.
func makeItem(
    _ label: String = UUID().uuidString,
    byteSize: Int = 10,
    usedDaysAgo: Double = 0,
    pinned: Bool = false
) -> ClipItem {
    let used = referenceDate.addingTimeInterval(-days(usedDaysAgo))
    return ClipItem(
        createdAt: used,
        lastUsedAt: used,
        kind: .text,
        contentHash: ClipContent.text(label).contentHash,
        sourceApp: nil,
        pinned: pinned,
        byteSize: byteSize,
        preview: label
    )
}

/// A throwaway store folder, removed when the test ends.
struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// A few bytes that stand in for PNG data; the store never decodes images.
let samplePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
