import Foundation
import ClipboardKit

/// Clipboard history preferences (plan section 5). History is off until switched on. The
/// defaults are injectable so tests use a scratch suite, never `com.docshot.app`.
struct ClipboardSettings: @unchecked Sendable {
    static let enabledKey = "DocShotClipboardHistoryEnabled"
    static let pausedKey = "DocShotClipboardHistoryPaused"
    static let clearKeepKey = "DocShotClipboardClearKeep"
    static let maxItemsKey = "DocShotClipboardMaxItems"
    static let maxAgeDaysKey = "DocShotClipboardMaxAgeDays"
    static let maxMegabytesKey = "DocShotClipboardMaxMegabytes"
    static let excludedAppsKey = "DocShotClipboardExcludedApps"
    static let pasteDirectlyKey = "DocShotClipboardPasteDirectly"
    static let accessRequestedKey = "DocShotClipboardAccessibilityRequested"

    /// The fixed choices in Settings (C3 plan, decision 6). `nil` items means no limit.
    static let itemChoices: [Int?] = [50, 100, 200, 500, nil]
    static let ageChoices = [7, 30, 90]
    static let megabyteChoices = [100, 250, 500, 1024]

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

    /// Unpinned items kept; nil means no limit. A value that is not one of the choices reads
    /// as the default.
    var maxItems: Int? {
        get {
            guard let stored = defaults.object(forKey: Self.maxItemsKey) as? Int else {
                return RetentionLimits.defaultMaxItems
            }
            if stored == 0 { return nil }
            return Self.itemChoices.contains(stored) ? stored : RetentionLimits.defaultMaxItems
        }
        nonmutating set { defaults.set(newValue ?? 0, forKey: Self.maxItemsKey) }
    }

    var maxAgeDays: Int {
        get {
            let stored = defaults.integer(forKey: Self.maxAgeDaysKey)
            return Self.ageChoices.contains(stored) ? stored : Int(RetentionLimits.defaultMaxAge / 86_400)
        }
        nonmutating set { defaults.set(newValue, forKey: Self.maxAgeDaysKey) }
    }

    var maxMegabytes: Int {
        get {
            let stored = defaults.integer(forKey: Self.maxMegabytesKey)
            return Self.megabyteChoices.contains(stored) ? stored : RetentionLimits.defaultMaxBytes / (1024 * 1024)
        }
        nonmutating set { defaults.set(newValue, forKey: Self.maxMegabytesKey) }
    }

    /// The limits the store applies.
    var limits: RetentionLimits {
        RetentionLimits(
            maxItems: maxItems ?? RetentionLimits.noItemLimit,
            maxAge: TimeInterval(maxAgeDays) * 86_400,
            maxBytes: maxMegabytes * 1024 * 1024
        )
    }

    /// Apps whose copies are never recorded; the defaults until the list is edited.
    var excludedApps: [String] {
        get {
            defaults.stringArray(forKey: Self.excludedAppsKey)
                ?? RecordingRules.defaultExcludedBundleIDs.sorted()
        }
        nonmutating set { defaults.set(newValue, forKey: Self.excludedAppsKey) }
    }

    /// Back to the default excluded apps.
    func restoreDefaultExcludedApps() {
        defaults.removeObject(forKey: Self.excludedAppsKey)
    }

    /// Paste into the previous app when Accessibility allows it. On unless switched off.
    var pasteDirectly: Bool {
        get { defaults.object(forKey: Self.pasteDirectlyKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.pasteDirectlyKey) }
    }

    /// The system's Accessibility request has been shown once (C3 plan, decision 2).
    var accessRequested: Bool {
        get { defaults.bool(forKey: Self.accessRequestedKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.accessRequestedKey) }
    }
}

extension ClipboardSettings {
    /// The confirmation for Clear, with the exact count (Quiet `patterns.md`, destructive actions).
    static func clearQuestion(_ count: Int) -> String {
        "Clear \(count.formatted()) item\(count == 1 ? "" : "s")?"
    }

    static let clearWarning = "This can't be undone."
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
