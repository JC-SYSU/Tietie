import Foundation

/// Free-text matching for search: normalized substring containment. Replaces the FTS5
/// unicode61 path, whose tokenizer treats a continuous CJK run as one token — a Chinese
/// substring mid-run ("机械取栓" inside "缺血性卒中机械取栓术后") could never match there.
/// Deliberately not fuzzy: the normalized query must appear contiguously.
enum TextMatch {
    /// Newest rows a text query scans before older history stops matching. FTS scanned
    /// the whole index; this window is the trade for substring semantics.
    static let candidateWindow = 10_000

    /// Case-folds and collapses whitespace runs to single spaces. Newlines between
    /// fields normalize to spaces too, so multi-word queries can span fields.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Every field a query can land in — the same set the FTS table indexed
    /// (plainText, title, linkTitle, appName, recognizedText).
    static func haystack(for item: ClipItem) -> String {
        normalize([item.plainText, item.title, item.linkTitle, item.appName, item.recognizedText]
            .compactMap { $0 }
            .joined(separator: "\n"))
    }

    /// Every whitespace-separated word of `normalizedQuery` must land somewhere in the
    /// item — AND semantics, order-free, each word a substring. A CJK run is a single
    /// word (no spaces), so Chinese keeps contiguous-substring behavior. This is FTS's
    /// `matchingAllPrefixesIn` AND with substrings instead of prefixes.
    /// `normalizedQuery` must be `normalize(_:)`d by the caller.
    static func matches(_ normalizedQuery: String, in item: ClipItem) -> Bool {
        guard !normalizedQuery.isEmpty else { return false }
        let hay = haystack(for: item)
        return normalizedQuery.split(separator: " ").allSatisfy { hay.contains($0) }
    }
}
