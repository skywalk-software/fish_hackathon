import Foundation

/// The status bar the game prints at the top of every turn, e.g.
/// ` Deck Nine        Score: 0        Moves: 4454`.
public struct StatusLine: Equatable, Sendable {
    public var location: String
    public var score: Int
    public var moves: Int

    public init(location: String, score: Int, moves: Int) {
        self.location = location
        self.score = score
        self.moves = moves
    }
}

/// One complete response from the game, everything printed between two prompts.
public struct GameTurn: Equatable, Sendable {
    /// What the game said, with status lines removed and surrounding blank lines trimmed.
    public var text: String
    /// The latest status line printed during this turn, if any.
    public var status: StatusLine?
    /// How the game is waiting for input after this turn.
    public var prompt: Prompt
    /// Objects the game moved this turn, from dfrotz's `-o` trace, in order.
    public var objectEvents: [ObjectEvent] = []

    public enum Prompt: Equatable, Sendable {
        /// The normal `>` command prompt.
        case command
        /// Any other line input, such as `Please enter a filename [planetfall.qzl]: `.
        /// The question text is the last line of `text`.
        case question
    }
}

/// A line from dfrotz's `-o` object-movement trace. Names are the objects' short
/// descriptions, so `.moved` holds "<object> <destination>" unsplit: both can contain
/// spaces, and only a caller who knows the object names can split them.
public enum ObjectEvent: Equatable, Sendable {
    /// `@move_obj Ensign First Class Deck Nine`
    case moved(String)
    /// `@remove_obj Ensign First Class`
    case removed(String)
}

/// Splits dfrotz's stdout into turns. Feed it raw chunks as they arrive.
///
/// A turn ends at the `>` command prompt. Other prompts (save/restore filenames)
/// don't end with `>`, so the caller decides when output has gone quiet and
/// calls `flushPending()`.
public struct FrotzOutputParser {
    private var buffer = ""

    public init() {}

    public var hasPendingOutput: Bool { !buffer.isEmpty }

    /// Adds output and returns any turns it completed.
    public mutating func consume(_ chunk: String) -> [GameTurn] {
        buffer += chunk
        var turns: [GameTurn] = []
        while let range = Self.promptRange(in: buffer) {
            let raw = String(buffer[..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            turns.append(Self.makeTurn(from: raw, prompt: .command))
        }
        return turns
    }

    /// Returns whatever output is buffered as a `.question` turn, for prompts that aren't `>`.
    public mutating func flushPending() -> GameTurn? {
        guard !buffer.isEmpty else { return nil }
        let raw = buffer
        buffer = ""
        return Self.makeTurn(from: raw, prompt: .question)
    }

    /// The command prompt is a `>` at the start of a line. Because the next turn's
    /// status line follows immediately with no newline, we match `\n>` anywhere
    /// rather than only at the end of the buffer.
    private static func promptRange(in text: String) -> Range<String.Index>? {
        if text.hasPrefix(">") { return text.startIndex..<text.index(after: text.startIndex) }
        return text.range(of: "\n>")
    }

    static func makeTurn(from raw: String, prompt: GameTurn.Prompt) -> GameTurn {
        var status: StatusLine?
        var objectEvents: [ObjectEvent] = []
        var kept: [Substring] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if let parsed = parseStatusLine(line) {
                status = parsed
            } else if let (event, before) = parseObjectEvent(line) {
                objectEvents.append(event)
                if !before.isEmpty { kept.append(before) }
            } else {
                kept.append(line)
            }
        }
        let text = kept.joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
        return GameTurn(text: text, status: status, prompt: prompt, objectEvents: objectEvents)
    }

    // Status lines start with a space, then the room name, a wide gap, and "Score: N   Moves: N".
    nonisolated(unsafe) private static let statusPattern =
        /^ (?<location>\S.*?)\s{2,}Score:\s*(?<score>-?\d+)\s+Moves:\s*(?<moves>\d+)\s*$/

    // dfrotz prints trace lines indented by three spaces. They normally sit on their own
    // line, but we also accept one at the end of a line of game text.
    nonisolated(unsafe) private static let objectEventPattern =
        /^(?<before>.*?) {3}@(?<op>move_obj|remove_obj) (?<args>.+)$/

    /// Returns the event plus any game text that preceded it on the same line.
    static func parseObjectEvent(_ line: Substring) -> (ObjectEvent, Substring)? {
        guard let match = line.wholeMatch(of: objectEventPattern) else { return nil }
        let args = String(match.args)
        let event: ObjectEvent = match.op == "move_obj" ? .moved(args) : .removed(args)
        return (event, match.before)
    }

    static func parseStatusLine(_ line: Substring) -> StatusLine? {
        guard let match = line.wholeMatch(of: statusPattern),
              let score = Int(match.score), let moves = Int(match.moves) else { return nil }
        return StatusLine(location: String(match.location), score: score, moves: moves)
    }
}
