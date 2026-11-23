import CryptoKit
import Foundation

/// What kind of thing was copied (plan section 4.2).
public enum ClipKind: String, Sendable, CaseIterable, Codable {
    case text
    case richText
    case image
    case fileURLs
    case colour
}

/// A colour in sRGB components from 0 to 1.
public struct ClipColour: Sendable, Equatable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
        self.red = clamp(red)
        self.green = clamp(green)
        self.blue = clamp(blue)
        self.alpha = clamp(alpha)
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when not fully opaque.
    public var hexString: String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        let rgb = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        return alpha < 1 ? rgb + String(format: "%02X", byte(alpha)) : rgb
    }

    /// Stable text form used for storage and the duplicate fingerprint.
    var storageString: String {
        String(format: "%.6f %.6f %.6f %.6f", red, green, blue, alpha)
    }

    init?(storageString: String) {
        let parts = storageString.split(separator: " ").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        self.init(red: parts[0], green: parts[1], blue: parts[2], alpha: parts[3])
    }
}

/// The content of one copy, already read from the pasteboard by the app side (C2).
public enum ClipContent: Sendable, Equatable {
    case text(String)
    /// Rich text keeps its RTF data and its plain-text form, for search and plain pasting.
    case richText(rtf: Data, plainText: String)
    /// Image data as copied (PNG or TIFF), with its type identifier such as `public.png`.
    case image(data: Data, typeIdentifier: String)
    case fileURLs([URL])
    case colour(ClipColour)

    public var kind: ClipKind {
        switch self {
        case .text: return .text
        case .richText: return .richText
        case .image: return .image
        case .fileURLs: return .fileURLs
        case .colour: return .colour
        }
    }

    /// The bytes that identify this content. Two copies with the same kind and the same
    /// canonical bytes are the same item.
    var canonicalBytes: Data {
        switch self {
        case .text(let string):
            return Data(string.utf8)
        case .richText(let rtf, _):
            return rtf
        case .image(let data, _):
            return data
        case .fileURLs(let urls):
            return Data(Self.joinedURLs(urls).utf8)
        case .colour(let colour):
            return Data(colour.storageString.utf8)
        }
    }

    /// SHA-256 of the kind and the canonical bytes, as lowercase hex (the de-duplication key).
    public var contentHash: String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: canonicalBytes)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The bytes this item holds, counted against the storage cap.
    public var byteSize: Int {
        switch self {
        case .richText(let rtf, let plainText):
            return rtf.count + plainText.utf8.count
        default:
            return canonicalBytes.count
        }
    }

    /// Short single-line text for the history list. Images have none; the list shows the
    /// image itself.
    public var preview: String {
        switch self {
        case .text(let string):
            return Self.singleLine(string)
        case .richText(_, let plainText):
            return Self.singleLine(plainText)
        case .image:
            return ""
        case .fileURLs(let urls):
            return Self.singleLine(urls.map { $0.isFileURL ? $0.lastPathComponent : $0.absoluteString }
                .joined(separator: ", "))
        case .colour(let colour):
            return colour.hexString
        }
    }

    public static let previewLength = 200

    static func singleLine(_ string: String) -> String {
        let collapsed = string
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        return collapsed.count > previewLength ? String(collapsed.prefix(previewLength)) + "…" : collapsed
    }

    static func joinedURLs(_ urls: [URL]) -> String {
        urls.map(\.absoluteString).joined(separator: "\n")
    }
}

/// One history entry, without its payload (plan section 4.2). The payload is loaded on demand
/// from the store.
public struct ClipItem: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public var lastUsedAt: Date
    public let kind: ClipKind
    public let contentHash: String
    public var sourceApp: String?
    public var pinned: Bool
    public let byteSize: Int
    public let preview: String

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        lastUsedAt: Date,
        kind: ClipKind,
        contentHash: String,
        sourceApp: String?,
        pinned: Bool,
        byteSize: Int,
        preview: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.kind = kind
        self.contentHash = contentHash
        self.sourceApp = sourceApp
        self.pinned = pinned
        self.byteSize = byteSize
        self.preview = preview
    }

    /// A new, unpinned item for `content`.
    public init(content: ClipContent, sourceApp: String?, now: Date, id: UUID = UUID()) {
        self.init(
            id: id,
            createdAt: now,
            lastUsedAt: now,
            kind: content.kind,
            contentHash: content.contentHash,
            sourceApp: sourceApp,
            pinned: false,
            byteSize: content.byteSize,
            preview: content.preview
        )
    }
}
