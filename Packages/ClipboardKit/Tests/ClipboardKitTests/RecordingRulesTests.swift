import Foundation
import Testing
@testable import ClipboardKit

@Suite("Recording rules (plan 4.3)")
struct RecordingRulesTests {
    let rules = RecordingRules()

    func change(
        _ types: [String] = ["public.utf8-plain-text"],
        app: String? = "com.apple.TextEdit",
        count: Int = 10
    ) -> ClipboardChange {
        ClipboardChange(changeCount: count, types: types, frontmostBundleID: app)
    }

    func decide(_ change: ClipboardChange, enabled: Bool = true, paused: Bool = false, own: Set<Int> = []) -> RecordDecision {
        rules.decide(change, historyEnabled: enabled, paused: paused, ownWriteChangeCounts: own)
    }

    @Test("An ordinary text copy is recorded")
    func testOrdinaryCopy() {
        #expect(decide(change()) == .record)
    }

    @Test("Nothing is recorded with history off")
    func testHistoryOff() {
        #expect(decide(change(), enabled: false) == .skip(.historyOff))
    }

    @Test("Nothing is recorded while paused")
    func testPaused() {
        #expect(decide(change(), paused: true) == .skip(.paused))
    }

    @Test("DocShot's own writes are ignored")
    func testOwnWrite() {
        #expect(decide(change(count: 42), own: [41, 42]) == .skip(.ownWrite))
        #expect(decide(change(count: 43), own: [41, 42]) == .record)
    }

    @Test("Concealed, transient and auto-generated markers are skipped", arguments: RecordingRules.skipMarkers)
    func testMarkers(marker: String) {
        let types = ["public.utf8-plain-text", marker]
        #expect(decide(change(types)) == .skip(.marker(marker)))
    }

    @Test("Copies made while an excluded app is in front are skipped",
          arguments: Array(RecordingRules.defaultExcludedBundleIDs).sorted())
    func testExcludedApps(app: String) {
        #expect(decide(change(app: app)) == .skip(.excludedApp(app)))
    }

    @Test("The default exclusions are Passwords, Keychain Access, Bitwarden and 1Password")
    func testDefaultExclusions() {
        #expect(RecordingRules.defaultExcludedBundleIDs == [
            "com.apple.Passwords", "com.apple.keychainaccess", "com.bitwarden.desktop",
            "com.1password.1password", "com.agilebits.onepassword7",
        ])
    }

    @Test("Exclusions can be changed")
    func testCustomExclusions() {
        let custom = RecordingRules(excludedBundleIDs: ["com.example.vault"])
        let fromVault = change(app: "com.example.vault")
        #expect(custom.decide(fromVault, historyEnabled: true, paused: false, ownWriteChangeCounts: []) == .skip(.excludedApp("com.example.vault")))
        let fromPasswords = change(app: "com.apple.Passwords")
        #expect(custom.decide(fromPasswords, historyEnabled: true, paused: false, ownWriteChangeCounts: []) == .record)
    }

    @Test("An unknown front app does not block recording")
    func testUnknownApp() {
        #expect(decide(change(app: nil)) == .record)
    }

    @Test("Types history does not keep are skipped")
    func testUnsupported() {
        #expect(decide(change(["com.example.private-type"])) == .skip(.unsupportedContent))
        #expect(decide(change([])) == .skip(.unsupportedContent))
    }

    @Test("A marker wins over an otherwise recordable copy, even from an excluded app")
    func testMarkerFirst() {
        let types = ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]
        #expect(decide(change(types, app: "com.apple.Passwords")) == .skip(.marker("org.nspasteboard.ConcealedType")))
    }
}
