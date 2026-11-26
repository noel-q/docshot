import Foundation

/// A newer DocShot build published on GitHub.
public struct AvailableUpdate: Equatable, Sendable, Codable {
    public let build: Int
    /// The marketing version from the tag, such as "1.1.0".
    public let version: String
    public let title: String
    /// The release notes, as plain text, shortened for the guide.
    public let notes: String
    /// The DMG attached to the release.
    public let downloadURL: URL
    /// The release page, for anything the guide does not cover.
    public let pageURL: URL

    public var displayVersion: String { "\(version) (build \(build))" }
}

/// Update notices (decided 26 November 2026): DocShot asks GitHub once a day whether a newer
/// build of noel-q/docshot is out and, if so, says so and shows how to update. It never
/// downloads or installs anything itself; the build is not notarised, so the user does it with
/// the guide. The pure rules live here; `UpdateController` does the asking.
public enum UpdateRelease {
    public static let releasesURL = URL(string: "https://api.github.com/repos/noel-q/docshot/releases?per_page=20")!
    /// A check is due when none has run for this long.
    public static let checkInterval: TimeInterval = 20 * 60 * 60
    /// Longest release notes shown in the guide.
    public static let maxNotesLength = 400

    /// Tags look like `macos-v1.1.0-build.2`: the version, then the build number the app
    /// compares against its own `CFBundleVersion`.
    public static func parseTag(_ tag: String) -> (version: String, build: Int)? {
        let prefix = "macos-v"
        guard tag.hasPrefix(prefix), let marker = tag.range(of: "-build.", options: .backwards) else { return nil }
        let version = String(tag[tag.index(tag.startIndex, offsetBy: prefix.count)..<marker.lowerBound])
        guard !version.isEmpty, version.allSatisfy({ $0.isNumber || $0 == "." }),
              let build = Int(tag[marker.upperBound...]), build > 0 else { return nil }
        return (version, build)
    }

    /// The newest release built after `currentBuild` that carries a DMG, from GitHub's releases
    /// JSON. Drafts are skipped; test builds may be pre-releases. Links must be GitHub https
    /// links, so a changed release can never send the user anywhere else. Throws when the answer
    /// is not a releases list (a proxy or sign-in page), so that never reads as "up to date".
    public static func newest(fromJSON data: Data, newerThan currentBuild: Int) throws -> AvailableUpdate? {
        let releases = try JSONDecoder().decode([Release].self, from: data)
        var best: AvailableUpdate?
        for release in releases where release.draft != true {
            guard let tag = parseTag(release.tag_name), tag.build > currentBuild,
                  tag.build > (best?.build ?? 0),
                  let page = URL(string: release.html_url ?? ""), isGitHubLink(page),
                  let dmg = release.assets?.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
                  let download = URL(string: dmg.browser_download_url), isGitHubLink(download) else { continue }
            let title = release.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            best = AvailableUpdate(
                build: tag.build,
                version: tag.version,
                title: title.isEmpty ? "DocShot \(tag.version)" : title,
                notes: shortNotes(release.body ?? ""),
                downloadURL: download,
                pageURL: page
            )
        }
        return best
    }

    public static func isCheckDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        // A clock set back also counts as due.
        return now.timeIntervalSince(lastCheck) >= checkInterval || now < lastCheck
    }

    /// The notice shows once per new build, and only while notices are on. The DocShot menu
    /// shows the update either way.
    public static func shouldNotify(_ update: AvailableUpdate, noticesOn: Bool, lastNotifiedBuild: Int) -> Bool {
        noticesOn && update.build > lastNotifiedBuild
    }

    static func isGitHubLink(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix(".githubusercontent.com")
    }

    /// Plain lines from Markdown notes: headings and list marks dropped, blank runs closed up.
    static func shortNotes(_ body: String) -> String {
        let lines = body.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> String in
                var text = line.trimmingCharacters(in: .whitespaces)
                while text.hasPrefix("#") { text.removeFirst() }
                if text.hasPrefix("- ") || text.hasPrefix("* ") { text = "• " + text.dropFirst(2) }
                return text.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")
        guard joined.count > maxNotesLength else { return joined }
        let cut = joined.prefix(maxNotesLength)
        let end = cut.lastIndex(where: { $0 == " " || $0 == "\n" }) ?? cut.endIndex
        return String(cut[..<end]) + "…"
    }

    private struct Release: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let draft: Bool?
        let html_url: String?
        let assets: [Asset]?
    }

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }
}
