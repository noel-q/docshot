import Foundation

/// How history search reads items (C3 plan, decision 3). Case, accents and character width are
/// ignored, and every word of the query must appear. Text and rich text are searched by their
/// full text, files by their paths, colours by their code. Images have no text until C4a.
public enum SearchText {

    /// The form both the query and the item text are compared in.
    public static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The folded words of a query; empty for a blank query.
    public static func terms(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// True when every term appears in the folded text.
    public static func matches(_ foldedText: String, terms: [String]) -> Bool {
        terms.allSatisfy { foldedText.contains($0) }
    }

    /// The searchable text of new content, before folding.
    public static func searchable(_ content: ClipContent) -> String {
        switch content {
        case .text(let string):
            return string
        case .richText(_, let plainText):
            return plainText
        case .image:
            return ""
        case .fileURLs(let urls):
            return urls.map(\.path).joined(separator: "\n")
        case .colour(let colour):
            return colour.hexString
        }
    }

    /// The searchable text of a stored item, from its saved text column.
    static func searchable(kind: ClipKind, payloadText: String?, preview: String) -> String {
        switch kind {
        case .text, .richText:
            return payloadText ?? preview
        case .image:
            return ""
        case .fileURLs:
            return (payloadText ?? "")
                .split(separator: "\n")
                .compactMap { URL(string: String($0))?.path }
                .joined(separator: "\n")
        case .colour:
            return preview
        }
    }
}
