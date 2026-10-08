import Foundation

/// Fish S2 delivery tags like "[dripping with sarcasm]" or "[warm]": Claude writes them into
/// the narrator's and SNARK-9's lines to direct how the voice reads them. Fish treats them as
/// direction rather than words, so they're spoken as-is but removed from anything shown on
/// screen or fed back to Claude as history.
public enum DeliveryTags {
    /// The text without tags. Also drops an unfinished tag at the end ("Oh, [dripping wi"),
    /// so a caption that's still streaming in never flashes half a tag.
    public static func strip(_ text: String) -> String {
        text.replacingOccurrences(of: #"\[[^\]]*\]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `text` might still be (or start) a tag that hasn't closed yet.
    static func hasOpenTag(_ text: String) -> Bool {
        text.range(of: #"\[[^\]]*$"#, options: .regularExpression) != nil
    }
}
