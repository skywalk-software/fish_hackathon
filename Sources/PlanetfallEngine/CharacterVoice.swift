import Foundation

/// A character who speaks aloud: which Fish Audio voice to use, and how the game's text
/// refers to them when it quotes them.
public struct CharacterVoice: Equatable, Sendable {
    /// Matches `GameCharacter.id` where the character has one.
    public var characterID: String
    /// Names that attribute a quote to this character ("Blather shouts ..."). The first is
    /// also how the narrator's text marks their lines ("[Blather speaks]").
    public var names: [String]
    /// Fish Audio voice model id, sent as `reference_id`.
    public var fishVoiceID: String

    public init(characterID: String, names: [String], fishVoiceID: String) {
        self.characterID = characterID
        self.names = names
        self.fishVoiceID = fishVoiceID
    }
}

/// Every voice in the game. Override any of them in `.env` with `FISH_VOICE_NARRATOR`,
/// `FISH_VOICE_SIDEKICK`, or `FISH_VOICE_<CHARACTER>` (e.g. FISH_VOICE_BLATHER).
public struct VoiceCast: Equatable, Sendable {
    /// Reads Claude's summary of each turn.
    public var narratorVoiceID: String
    /// SNARK-9, the let's-play commentator.
    public var sidekickVoiceID: String
    public var characters: [CharacterVoice]

    public init(narratorVoiceID: String, sidekickVoiceID: String, characters: [CharacterVoice]) {
        self.narratorVoiceID = narratorVoiceID
        self.sidekickVoiceID = sidekickVoiceID
        self.characters = characters
    }

    /// Fish voice library picks, plus "arnold" for Blather. Arnold is an unlisted voice in Gaurav's
    /// Fish account: usable with any API key that has its id, but not listed in Fish's library.
    public static let defaults = VoiceCast(
        narratorVoiceID: "e686ae649ee44f219a108aacba206c1a",  // "calm storyteller male"
        sidekickVoiceID: "fe5b8eaa8b754a5b8d895265def9e5b2",  // "Robot": monotone sci-fi drone
        characters: [
            CharacterVoice(characterID: "blather", names: ["Blather"],
                           fishVoiceID: "546972d2053c481d86fe4449a1b54e27"),  // "arnold"
            CharacterVoice(characterID: "floyd", names: ["Floyd"],
                           fishVoiceID: "4fcb3a423c61415fb35604eba567d95f"),  // "Energetic Child"
            // Only named inside her first line, so "the woman" attributes it. "Woman" appears
            // nowhere else in the game.
            CharacterVoice(characterID: "veldina", names: ["Veldina", "woman"],
                           fishVoiceID: "8906b5268cae414fb9b8d3da6e84413d"),  // "Measured Storyteller"
        ])

    public static func load() -> VoiceCast {
        load(environment: ProcessInfo.processInfo.environment, envFile: FishAPIKey.envFileURL)
    }

    static func load(environment: [String: String], envFile: URL) -> VoiceCast {
        func override(_ role: String, _ voiceID: String) -> String {
            let name = "FISH_VOICE_" + role.uppercased().replacingOccurrences(of: "-", with: "_")
            return DotEnv.value(for: name, environment: environment, envFile: envFile) ?? voiceID
        }
        var cast = defaults
        cast.narratorVoiceID = override("narrator", cast.narratorVoiceID)
        cast.sidekickVoiceID = override("sidekick", cast.sidekickVoiceID)
        cast.characters = cast.characters.map { voice in
            var voice = voice
            voice.fishVoiceID = override(voice.characterID, voice.fishVoiceID)
            return voice
        }
        return cast
    }
}

/// A line of dialogue from the game text, attributed to a voiced character.
public struct SpokenLine: Equatable, Sendable {
    public var characterID: String
    /// What they say, with consecutive quotes from the same paragraph joined.
    public var text: String
    /// The same words with Fish S2 delivery tags like "[shouting]" taken from the verbs
    /// around each quote ("he sneers", "bellows Blather").
    public var ttsText: String
}

/// One turn split between the narrator and the characters.
public struct TurnScript: Equatable, Sendable {
    /// The turn's text with each character line replaced by a marker like "[Blather speaks]",
    /// so the narrator can describe the scene without speaking for anyone.
    public var narration: String
    public var lines: [SpokenLine]
}

/// Finds quoted speech by voiced characters in a turn of game output.
///
/// Within a paragraph, a quote belongs to the nearest character name before it
/// (`Blather shouts "..."`), or failing that the nearest one after it (`"..." bellows Blather`).
/// Quotes in paragraphs that don't name a voiced character (parser messages like
/// `I don't know the word "sorry."`) and quoted signs (`a card labelled "..."`) stay narration.
public enum DialogueExtractor {
    public static func script(for text: String, voices: [CharacterVoice]) -> TurnScript {
        var narration: [String] = []
        var lines: [SpokenLine] = []
        for paragraph in paragraphs(in: text) {
            let split = script(forParagraph: paragraph, voices: voices)
            narration.append(split.narration)
            lines += split.lines
        }
        return TurnScript(narration: narration.joined(separator: "\n\n"), lines: lines)
    }

    public static func lines(in text: String, voices: [CharacterVoice]) -> [SpokenLine] {
        script(for: text, voices: voices).lines
    }

    /// Paragraphs are separated by blank lines; dfrotz wraps long ones at 255 columns.
    static func paragraphs(in text: String) -> [String] {
        text.split(separator: /\n[ \t]*\n/).map { paragraph in
            paragraph.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }.filter { !$0.isEmpty }
    }

    private struct Mention {
        let voice: CharacterVoice
        let range: Range<String.Index>
    }

    private static func script(forParagraph paragraph: String, voices: [CharacterVoice]) -> TurnScript {
        let quotes = paragraph.matches(of: /"([^"]+)"/)
        let quoteRanges = quotes.map(\.range)
        let mentions = voices.flatMap { voice in
            voice.names.flatMap { name in
                paragraph.ranges(of: wordPattern(name)).map { Mention(voice: voice, range: $0) }
            }
        }.filter { mention in !quoteRanges.contains { $0.overlaps(mention.range) } }
        guard !quotes.isEmpty, !mentions.isEmpty else { return TurnScript(narration: paragraph, lines: []) }

        var narration = ""
        var narrated = paragraph.startIndex
        var lines: [SpokenLine] = []
        var lastDirection: String?
        for (index, quote) in quotes.enumerated() {
            let previousEnd = index > 0 ? quotes[index - 1].range.upperBound : paragraph.startIndex
            let lead = paragraph[previousEnd..<quote.range.lowerBound]
            guard !introducesWrittenText(lead) else { continue }
            let before = mentions.filter { $0.range.upperBound <= quote.range.lowerBound }
                .max { $0.range.lowerBound < $1.range.lowerBound }
            let after = mentions.filter { $0.range.lowerBound >= quote.range.upperBound }
                .min { $0.range.lowerBound < $1.range.lowerBound }
            guard let speaker = (before ?? after)?.voice else { continue }

            narration += paragraph[narrated..<quote.range.lowerBound] + "[\(speaker.names[0]) speaks]"
            narrated = quote.range.upperBound

            let words = String(quote.output.1).trimmingCharacters(in: .whitespaces)
            let nextStart = index + 1 < quotes.count ? quotes[index + 1].range.lowerBound : paragraph.endIndex
            // The sentence right after the quote ("he sneers.") says how it was delivered, else the
            // one right before it ("Blather shouts", "Blather's sneer softens a bit.").
            let direction = direction(in: firstSentence(paragraph[quote.range.upperBound..<nextStart]))
                ?? direction(in: lastSentence(lead))

            if var last = lines.last, last.characterID == speaker.characterID {
                // A later quote in the same breath: keep its tag only if the delivery changes.
                let tag = direction != nil && direction != lastDirection ? "[\(direction!)] " : ""
                last.text += " " + words
                last.ttsText += " " + tag + words
                lines[lines.count - 1] = last
            } else {
                lines.append(SpokenLine(characterID: speaker.characterID, text: words,
                                        ttsText: (direction.map { "[\($0)] " } ?? "") + words))
            }
            if direction != nil { lastDirection = direction }
        }
        narration += paragraph[narrated...]
        return TurnScript(narration: narration, lines: lines)
    }

    /// Words just before a quote that mark it as writing, not speech: `labelled "Spam and Egz"`.
    private static func introducesWrittenText(_ lead: Substring) -> Bool {
        let nearby = lead.suffix(30).lowercased()
        return ["label", "reads", "embossed", "marked", "painted", "written", "inscribed", "engraved",
                "titled", "the word", "sign"].contains { nearby.contains($0) }
    }

    /// Speech verbs near a quote, mapped to Fish S2 inline tags. Checked in order, so
    /// "his sneer softens" reads as grudging rather than sneering.
    private static let cues: [(stems: [String], tag: String)] = [
        (["soften"], "grudgingly"),
        (["bellow", "shout", "yell", "scream", "roar", "bark", "howl"], "shouting"),
        (["sneer"], "sneering"),
        (["giggl", "laugh"], "laughing"),
        (["whimper", "sniff", "sob", "sad"], "sad"),
        (["grin", "impish"], "playful"),
        (["growl", "snarl"], "growling"),
        (["mutter", "mumble"], "muttering"),
        (["whisper"], "whispering"),
        (["lilting"], "gentle"),
    ]

    static func direction(in context: some StringProtocol) -> String? {
        let lowered = context.lowercased()
        return cues.first { $0.stems.contains { lowered.contains($0) } }?.tag
    }

    private static func isSentenceEnd(_ character: Character) -> Bool {
        character == "." || character == "!" || character == "?"
    }

    static func firstSentence(_ text: Substring) -> Substring {
        guard let end = text.firstIndex(where: isSentenceEnd) else { return text }
        return text[...end]
    }

    static func lastSentence(_ text: Substring) -> Substring {
        var body = text
        while let last = body.last, last.isWhitespace { body = body.dropLast() }
        if let last = body.last, isSentenceEnd(last) { body = body.dropLast() }
        guard let start = body.lastIndex(where: isSentenceEnd) else { return body }
        return body[body.index(after: start)...]
    }

    private static func wordPattern(_ name: String) -> Regex<AnyRegexOutput> {
        // Simple boundaries, so "Blather's" still counts as naming Blather.
        try! Regex("\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b").wordBoundaryKind(.simple)
    }
}
