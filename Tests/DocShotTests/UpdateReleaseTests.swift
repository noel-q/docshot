import Foundation
import Testing
@testable import DocShot

/// Update notices: reading GitHub's releases JSON and deciding when to tell the user.
@Suite("Update releases")
struct UpdateReleaseTests {
    static func release(
        tag: String, draft: Bool = false, prerelease: Bool = true, name: String? = nil, body: String = "",
        page: String = "https://github.com/noel-q/docshot/releases/tag/X",
        dmg: String? = "https://github.com/noel-q/docshot/releases/download/X/DocShot-macos-development.dmg"
    ) -> [String: Any] {
        var release: [String: Any] = [
            "tag_name": tag, "draft": draft, "prerelease": prerelease, "body": body, "html_url": page,
            "assets": dmg.map { [["name": "DocShot-macos-development.dmg", "browser_download_url": $0]] } ?? [],
        ]
        if let name { release["name"] = name }
        return release
    }

    static func json(_ releases: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: releases)
    }

    @Test("Tags give the version and build; other tags are ignored")
    func testParseTag() {
        #expect(UpdateRelease.parseTag("macos-v1.1.0-build.2")! == ("1.1.0", 2))
        #expect(UpdateRelease.parseTag("macos-v1.0.0") == nil)
        #expect(UpdateRelease.parseTag("macos-v-build.3") == nil)
        #expect(UpdateRelease.parseTag("windows-v1.1.0-build.3") == nil)
        #expect(UpdateRelease.parseTag("macos-v1.1.0-build.0") == nil)
        #expect(UpdateRelease.parseTag("macos-v1.1.0-build.x") == nil)
    }

    @Test("The newest build above ours with a DMG wins; drafts, older builds and releases without a DMG do not")
    func testNewest() throws {
        let data = Self.json([
            Self.release(tag: "macos-v1.1.0-build.3", name: "Test build 3", body: "## Fixes\n- Clear works\n\n- Copy GIF"),
            Self.release(tag: "macos-v1.1.0-build.5", draft: true),
            Self.release(tag: "macos-v1.1.0-build.4", dmg: nil),
            Self.release(tag: "macos-v1.1.0-build.2"),
            Self.release(tag: "macos-v1.0.0"),
        ])
        let update = try #require(UpdateRelease.newest(fromJSON: data, newerThan: 2))
        #expect(update.build == 3)
        #expect(update.version == "1.1.0")
        #expect(update.title == "Test build 3")
        #expect(update.notes == "Fixes\n• Clear works\n• Copy GIF")
        #expect(update.downloadURL.lastPathComponent == "DocShot-macos-development.dmg")
        #expect(update.displayVersion == "1.1.0 (build 3)")

        #expect(UpdateRelease.newest(fromJSON: data, newerThan: 3) == nil)
        #expect(UpdateRelease.newest(fromJSON: Data("not json".utf8), newerThan: 1) == nil)
    }

    @Test("Links that are not GitHub https links are refused")
    func testLinks() {
        let elsewhere = Self.json([Self.release(tag: "macos-v1.1.0-build.3", dmg: "https://example.com/DocShot.dmg")])
        #expect(UpdateRelease.newest(fromJSON: elsewhere, newerThan: 1) == nil)
        let plain = Self.json([Self.release(tag: "macos-v1.1.0-build.3", page: "http://github.com/noel-q/docshot")])
        #expect(UpdateRelease.newest(fromJSON: plain, newerThan: 1) == nil)
        let lookalike = Self.json([Self.release(tag: "macos-v1.1.0-build.3", dmg: "https://github.com.evil.example/x.dmg")])
        #expect(UpdateRelease.newest(fromJSON: lookalike, newerThan: 1) == nil)
    }

    @Test("Long notes are cut at a word with an ellipsis")
    func testLongNotes() throws {
        let body = String(repeating: "word ", count: 200)
        let update = try #require(UpdateRelease.newest(fromJSON: Self.json([Self.release(tag: "macos-v1.1.0-build.3", body: body)]), newerThan: 1))
        #expect(update.notes.count <= UpdateRelease.maxNotesLength + 1)
        #expect(update.notes.hasSuffix("word…"))
    }

    @Test("A check is due after 20 hours, at first, or when the clock went back")
    func testCheckDue() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UpdateRelease.isCheckDue(lastCheck: nil, now: now))
        #expect(!UpdateRelease.isCheckDue(lastCheck: now.addingTimeInterval(-60 * 60), now: now))
        #expect(UpdateRelease.isCheckDue(lastCheck: now.addingTimeInterval(-21 * 60 * 60), now: now))
        #expect(UpdateRelease.isCheckDue(lastCheck: now.addingTimeInterval(60 * 60), now: now))
    }

    @Test("The notice shows once per build, and never with notices off")
    func testNotify() throws {
        let update = try #require(UpdateRelease.newest(fromJSON: Self.json([Self.release(tag: "macos-v1.1.0-build.3")]), newerThan: 2))
        #expect(UpdateRelease.shouldNotify(update, noticesOn: true, lastNotifiedBuild: 0))
        #expect(!UpdateRelease.shouldNotify(update, noticesOn: true, lastNotifiedBuild: 3))
        #expect(!UpdateRelease.shouldNotify(update, noticesOn: false, lastNotifiedBuild: 0))
    }
}
