import Foundation

/// DocShot's four easter eggs (27 November 2026, Noel's choice), and the guardrails that keep
/// them from appearing by accident (Quiet's Signature rules): a search egg needs the whole
/// search to be its phrase, and the Konami code needs all ten keys in order, quickly, with no
/// other key between. Nothing here is stored, sent or written into captures. Foundation only,
/// so both test targets check it.
public enum SearchEgg: String, CaseIterable, Sendable, Identifiable {
    /// A thank-you to the testers.
    case hello = "hello docshot"
    /// Unlocks the hidden Rose and Lavender themes.
    case bloom = "in bloom"
    /// Quiet's Signature for DocShot: the ember square and Noel's line.
    case signature = "made by noel"

    public var id: String { rawValue }

    /// The egg whose phrase is the whole search, ignoring case, outer spaces and repeated
    /// spaces. A search that only contains a phrase ("noel", "made by noel's team") is never one.
    public static func egg(forQuery query: String) -> SearchEgg? {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        return SearchEgg(rawValue: words.joined(separator: " "))
    }

    public var title: String {
        switch self {
        case .hello: return "Hello"
        case .bloom: return "Two themes have bloomed"
        case .signature: return "Made quietly by Noel."
        }
    }

    public var detail: String {
        switch self {
        case .hello:
            return "Thank you for testing DocShot. Every problem you report makes it better."
        case .bloom:
            return "Rose and Lavender are now in Settings, under Appearance."
        case .signature:
            return "The small square is the end of Noel's mark, and the one in DocShot's icon."
        }
    }
}

/// The card the Konami code leaves in the clipboard window, after the snapshot flies to the
/// menu bar (27 November 2026).
public enum KonamiEgg {
    public static let title = "Up, up, down, down"
    public static let detail = "You found it. DocShot just took a picture of itself."
}

/// A key that can be part of the Konami code.
public enum KonamiKey: Sendable, Equatable {
    case up, down, left, right, b, a

    /// The key for a key press, or nil for any other key. Arrow key codes are macOS virtual key
    /// codes; letters only count with no Command, Option, Control or Shift.
    public static func from(keyCode: UInt16, characters: String?, hasModifiers: Bool) -> KonamiKey? {
        if hasModifiers { return nil }
        switch keyCode {
        case 126: return .up
        case 125: return .down
        case 123: return .left
        case 124: return .right
        default: break
        }
        switch characters {
        case "b": return .b
        case "a": return .a
        default: return nil
        }
    }
}

/// Matches up, up, down, down, left, right, left, right, B, A.
public struct KonamiTracker: Sendable {
    public static let sequence: [KonamiKey] = [.up, .up, .down, .down, .left, .right, .left, .right, .b, .a]
    /// The longest gap between two keys of the code. A slower run starts again.
    public static let maxGap: TimeInterval = 1.5

    private var matched = 0
    private var lastTime: TimeInterval = 0

    public init() {}

    /// Records one key press (nil for a key outside the code). True when it completes the code;
    /// the tracker then starts again, so the code must be typed in full each time.
    public mutating func record(_ key: KonamiKey?, at time: TimeInterval) -> Bool {
        if matched > 0, time - lastTime > Self.maxGap { matched = 0 }
        lastTime = time
        guard let key else {
            matched = 0
            return false
        }
        if key == Self.sequence[matched] {
            matched += 1
        } else {
            // A wrong key may still start the code again: a third up keeps the last two.
            matched = key == .up ? (matched == 2 ? 2 : 1) : 0
        }
        if matched == Self.sequence.count {
            matched = 0
            return true
        }
        return false
    }
}
