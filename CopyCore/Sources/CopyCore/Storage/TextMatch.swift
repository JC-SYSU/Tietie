import Foundation

/// Free-text matching for search: case-insensitive word containment. Replaces the
/// FTS5 unicode61 path, whose tokenizer treats a continuous CJK run as one token —
/// a Chinese substring mid-run ("机械取栓" inside "缺血性卒中机械取栓术后") could never
/// match there. Deliberately not fuzzy: every query word must appear contiguously.
/// A CJK run is a single word (no spaces), so Chinese keeps substring behavior.
/// ItemStore narrows candidates with a SQL LIKE prefilter first; this type is the
/// matching authority on whatever rows survive it.
enum TextMatch {
    /// Case-folds and collapses whitespace runs to single spaces.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Whitespace-separated words of a normalized query. AND semantics, order-free —
    /// the semantics FTS's `matchingAllPrefixesIn` had.
    static func words(_ normalizedQuery: String) -> [String] {
        normalizedQuery.split(separator: " ").map(String.init)
    }

    /// LIKE pattern for one word, with %, _ and \ escaped (pair with ESCAPE '\').
    static func likePattern(_ word: String) -> String {
        "%" + word
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
    }

    /// Whether a LIKE prefilter for `word` (already lowercased) also needs its
    /// upper-case spelling. SQLite's LIKE folds ASCII case on its own, so a Latin word
    /// needs only one pattern; a word carrying a non-ASCII cased letter (é, ü, …) needs
    /// the second. Words with no case at all (CJK) never do.
    static func prefilterNeedsUppercase(_ word: String) -> Bool {
        word.uppercased() != word && word.contains { !$0.isASCII }
    }

    /// Every field a query can land in — the same set the FTS table indexed
    /// (plainText, title, linkTitle, appName, recognizedText). Raw, unnormalized:
    /// normalizing every row per keystroke was the search bottleneck.
    static func haystack(for item: ClipItem) -> String {
        [item.plainText, item.title, item.linkTitle, item.appName, item.recognizedText]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    /// `words` must be `words(of:)` output. Newlines between fields let a multi-word
    /// query span fields — "safari invoice" matches an item copied from Safari
    /// holding "invoice".
    static func matches(_ words: [String], in item: ClipItem) -> Bool {
        guard !words.isEmpty else { return false }
        let hay = haystack(for: item)
        return words.allSatisfy {
            hay.range(of: $0, options: .caseInsensitive, locale: nil) != nil
        }
    }
}
