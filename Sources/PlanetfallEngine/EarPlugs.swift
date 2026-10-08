import Foundation

/// An app-side command: PLUG YOUR EARS (and variations) works anywhere and silences the red
/// alert siren until the player unplugs them. Like `Nap`, it never reaches the game, so no
/// game time passes; the player sees a short response, and the narrator and SNARK-9 react to
/// it like any other turn. Everything else (voices, other sound effects) keeps playing.
public enum EarPlugs {
    public enum Command: Equatable {
        case plug, unplug
    }

    /// The command `line` asks for, if it's about plugging or unplugging ears.
    public static func command(in line: String) -> Command? {
        // Lowercase, drop punctuation and filler words: "Put my fingers in my ears!" ->
        // "put fingers in ears".
        let filler: Set<String> = ["my", "your", "the", "both", "own", "a", "please"]
        let words = line.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty && !filler.contains($0) }
        guard words.contains(where: { ["ear", "ears", "earplug", "earplugs"].contains($0) }) else { return nil }
        let phrase = words.joined(separator: " ")

        let unplugPatterns = [
            #"^(unplug|uncover|unblock|unstop|open|clear) ears?$"#,
            #"^(take|pull|remove|get) fingers? out( of)? ears?$"#,
            #"^(take|pull|remove|get) (out )?(earplugs?|plugs?)( out)?( of| from)?( ears?)?$"#,
            #"^(remove|take out|pull out) fingers? from ears?$"#,
            #"^stop (plugging|covering|blocking) ears?$"#,
        ]
        let plugPatterns = [
            #"^(plug|cover|block|stop up|stop|muffle|shield|protect|close) ears?( up)?$"#,
            #"^(plug up|cover up|block up) ears?$"#,
            #"^(put|stick|jam|stuff|shove|press|push) fingers? (in|into) ears?$"#,
            #"^(put|stick|jam|stuff) ears? (with fingers?)?$"#,
            #"^(put|stick) (in )?(earplugs?|plugs?)( in( to)? ears?)?$"#,
        ]
        func matches(_ patterns: [String]) -> Bool {
            patterns.contains { phrase.range(of: $0, options: .regularExpression) != nil }
        }
        if matches(unplugPatterns) { return .unplug }
        if matches(plugPatterns) { return .plug }
        return nil
    }

    /// What the player sees for a command, given whether their ears were already plugged.
    static func response(to command: Command, wasPlugged: Bool) -> String {
        switch (command, wasPlugged) {
        case (.plug, false):
            "You jam your fingers firmly into your ears. The world goes muffled and far away."
        case (.plug, true):
            "Your ears are already plugged. Push any harder and you'll be poking your brain."
        case (.unplug, true):
            "You pull your fingers out of your ears, and the noise of the ship comes rushing back."
        case (.unplug, false):
            "Your ears aren't plugged. Everything is exactly as loud as it sounds."
        }
    }
}

/// Commands the app handles itself instead of the game's parser.
public enum AppCommands {
    /// Whether `line` is handled by the app wherever the player is (ear commands), or could
    /// be (SLEEP, which the app only takes over on Deck Nine before the explosion; elsewhere
    /// the game answers it). Voice input sends these as heard, skipping the game-vocabulary
    /// check, since words like "ears" and "nap" aren't in the game's dictionary.
    public static func recognizes(_ line: String) -> Bool {
        EarPlugs.command(in: line) != nil || Nap.isNapCommand(line)
    }
}
