import Foundation

/// An app-side change to the game: SLEEP on Deck Nine before the Feinstein explodes lets the
/// player doze until something happens, instead of the game's "You're not tired!".
///
/// The game itself is unchanged. `GameSession` sends WAIT until the explosion (or the alien
/// ambassador arriving) wakes the player, hides those turns from observers, so neither
/// SNARK-9 (Claude) nor the voices (Fish) run during the nap, then delivers one combined
/// turn describing the nap and the wake-up. Blather visiting doesn't wake the player: on
/// Deck Nine he only hands out demerits, which the game doesn't track.
public enum Nap {
    /// What the player can type to nap (compared after lowercasing and trimming).
    static let commands: Set<String> = ["sleep", "nap", "take a nap", "take nap", "go to sleep",
                                        "doze", "doze off", "fall asleep"]

    /// The most WAITs one nap sends. The explosion comes within about ten turns of the start;
    /// this just guarantees a nap ends.
    static let maxTurns = 30

    static func isNapCommand(_ line: String) -> Bool {
        let words = line.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return commands.contains(words)
    }

    /// Whether a nap applies here: on Deck Nine before the explosion, standing in the room.
    static func applies(location: String?, storyEvents: [String], playerHolder: String?) -> Bool {
        location == "Deck Nine" && !storyEvents.contains("explosion")
            && (playerHolder == nil || playerHolder == "Deck Nine")
    }

    public enum WakeReason: Equatable, Sendable {
        case explosion, ambassador, other
    }

    /// Why this hidden turn ends the nap, or nil to keep sleeping.
    static func wakeReason(for turn: GameTurn, napTurns: Int) -> WakeReason? {
        if turn.text.contains("A massive explosion rocks the ship") { return .explosion }
        if turn.objectEvents.contains(.moved("alien ambassador Deck Nine")) { return .ambassador }
        if turn.prompt != .command || napTurns >= maxTurns { return .other }
        return nil
    }

    /// Whether Blather came by during this turn (he's slept through, but it gets a mention).
    static func blatherVisited(in turn: GameTurn) -> Bool {
        turn.objectEvents.contains(.moved("Ensign First Class Deck Nine"))
    }

    /// The single turn the player sees for the whole nap.
    static func wakeText(final turn: GameTurn, reason: WakeReason, blatherVisited: Bool) -> String {
        var parts = ["You lean on your trusty scrub brush, close your eyes, and doze off right there on Deck Nine."]
        if blatherVisited {
            parts.append("Somewhere far away, a voice is bellowing about demerits. You sleep right through it.")
        }
        switch reason {
        case .explosion: parts.append("You wake with a start!")
        case .ambassador: parts.append("A loud, wet wheezing wakes you.")
        case .other: parts.append("You wake up, a little stiff.")
        }
        // WAIT's own "Time passes..." is redundant after a nap.
        let gameText = turn.text
            .replacingOccurrences(of: "Time passes...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !gameText.isEmpty { parts.append(gameText) }
        return parts.joined(separator: "\n\n")
    }
}
