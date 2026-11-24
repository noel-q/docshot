import ClipboardKit
import Foundation

/// The words the preview pane shows (restyle plan, decision 7). Pure, so both test targets
/// check them. Local only: nothing here reaches the network.
enum ClipPreviewText {

    /// Apps whose copied text is code: shown in a fixed-width font.
    static let codeSourceApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
        "com.sublimetext.4", "com.panic.Nova", "com.google.antigravity",
    ]

    static func isCodeSource(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return codeSourceApps.contains(bundleID) || bundleID.hasPrefix("com.jetbrains.")
    }

    /// The site of a text item that is one web link, from the address alone ("www." dropped).
    static func linkHost(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PasteboardReader.isLinkOnly(trimmed), let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func rgb(_ colour: ClipColour) -> String {
        "rgb(\(byte(colour.red)) \(byte(colour.green)) \(byte(colour.blue)))"
    }

    /// Hue in degrees, saturation and lightness in per cent, rounded.
    static func hsl(_ colour: ClipColour) -> String {
        let r = colour.red, g = colour.green, b = colour.blue
        let high = max(r, g, b), low = min(r, g, b)
        let lightness = (high + low) / 2
        let delta = high - low
        var hue = 0.0, saturation = 0.0
        if delta > 0 {
            saturation = delta / (1 - abs(2 * lightness - 1))
            switch high {
            case r: hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: hue = 60 * ((b - r) / delta + 2)
            default: hue = 60 * ((r - g) / delta + 4)
            }
            if hue < 0 { hue += 360 }
        }
        return "hsl(\(Int(hue.rounded()) % 360) \(Int((saturation * 100).rounded()))% \(Int((lightness * 100).rounded()))%)"
    }

    private static func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }

    /// The Size line: characters for text, pixels and bytes for images, a count for files.
    static func size(of content: ClipContent, pixelSize: CGSize?, byteSize: Int) -> String {
        switch content {
        case .text(let text):
            return count(text.count, "character")
        case .richText(_, let plain):
            return count(plain.count, "character")
        case .image:
            let bytes = ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
            guard let pixelSize else { return bytes }
            return "\(Int(pixelSize.width)) × \(Int(pixelSize.height)) pixels, \(bytes)"
        case .fileURLs(let urls):
            return count(urls.count, "file")
        case .colour(let colour):
            return colour.alpha < 1 ? "\(Int((colour.alpha * 100).rounded()))% opacity" : "Opaque"
        }
    }

    static func count(_ value: Int, _ noun: String) -> String {
        "\(value.formatted()) \(noun)\(value == 1 ? "" : "s")"
    }
}
