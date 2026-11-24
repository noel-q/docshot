import Foundation
import ClipboardKit

/// Clipboard history preferences (plan section 5). History is off until switched on. The
/// defaults are injectable so tests use a scratch suite, never `com.docshot.app`.
struct ClipboardSettings: @unchecked Sendable {
    static let enabledKey = "DocShotClipboardHistoryEnabled"
    static let pausedKey = "DocShotClipboardHistoryPaused"
    static let clearKeepKey = "DocShotClipboardClearKeep"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Off unless the user switched it on.
    var historyEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var paused: Bool {
        get { defaults.bool(forKey: Self.pausedKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.pausedKey) }
    }

    /// What a Clear leaves behind; pinned only unless chosen otherwise.
    var clearKeep: ClearKeep {
        get {
            defaults.string(forKey: Self.clearKeepKey).flatMap(ClearKeep.init(rawValue:)) ?? .defaultValue
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.clearKeepKey) }
    }
}

extension ClearKeep {
    /// Label for Settings and the Clear confirmation.
    var title: String {
        switch self {
        case .lastFive: return "Last 5 and pinned"
        case .lastTen: return "Last 10 and pinned"
        case .pinnedOnly: return "Pinned only"
        case .nothing: return "Nothing"
        }
    }
}
