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
    /// For characters the game only paraphrases ("The ambassador asks where Admiral Smithers can
    /// be found."): the game's exact wording, and what the character says aloud instead.
    public var reportedSpeech: [ReportedSpeech]

    public init(characterID: String, names: [String], fishVoiceID: String, reportedSpeech: [ReportedSpeech] = []) {
        self.characterID = characterID
        self.names = names
        self.fishVoiceID = fishVoiceID
        self.reportedSpeech = reportedSpeech
    }
}

/// Speech the game reports instead of quoting, turned into a line the character speaks.
public struct ReportedSpeech: Equatable, Sendable {
    /// The game's wording, matched exactly within a paragraph (wrapping doesn't matter).
    public var phrase: String
    /// What the character says, with any Fish S2 delivery tags.
    public var line: String

    public init(_ phrase: String, says line: String) {
        self.phrase = phrase
        self.line = line
    }
}

/// Every voice in the game. Override any of them in `.env` with `FISH_VOICE_NARRATOR`,
/// `FISH_VOICE_SIDEKICK`, or `FISH_VOICE_<CHARACTER>` (e.g. FISH_VOICE_BLATHER).
public struct VoiceCast: Equatable, Sendable {
    /// Reads Claude's summary of each turn.
    public var narratorVoiceID: String
    /// SNARK-9, the let's-play commentator.
    public var sidekickVoiceID: String
    /// Speaking speed for the narrator (1 is the voice's natural pace). Override with
    /// FISH_SPEED_NARRATOR in `.env`.
    public var narratorSpeed: Double = 1.1
    public var characters: [CharacterVoice]

    public init(narratorVoiceID: String, sidekickVoiceID: String, characters: [CharacterVoice]) {
        self.narratorVoiceID = narratorVoiceID
        self.sidekickVoiceID = sidekickVoiceID
        self.characters = characters
    }

    /// Fish voice library picks, plus custom unlisted voices: "arnold" for Blather (Gaurav's Fish
    /// account), and the narrator and SNARK-9, designed with `swift run audition design` and
    /// saved from the chosen candidates. Unlisted voices work with any API key that has the id
    /// but aren't listed in Fish's library.
    public static let defaults = VoiceCast(
        narratorVoiceID: "8cf8a1fb6e504334941905c844b2a78f",  // "Planetfall Narrator (American female)"
        sidekickVoiceID: "7fb628f6c7f44f19bf1c2cfaf13e5e24",  // "SNARK-9 (British)": Monty Python-style
        characters: [
            CharacterVoice(characterID: "blather", names: ["Blather"],
                           fishVoiceID: "546972d2053c481d86fe4449a1b54e27"),  // "arnold"
            // Before he introduces himself, the game calls him "the robot".
            CharacterVoice(characterID: "floyd", names: ["Floyd", "robot"],
                           fishVoiceID: "4fcb3a423c61415fb35604eba567d95f"),  // "Energetic Child"
            // Only named inside her first line, so "the woman" attributes it. "Woman" appears
            // nowhere else in the game.
            CharacterVoice(characterID: "veldina", names: ["Veldina", "woman"],
                           fishVoiceID: "8906b5268cae414fb9b8d3da6e84413d"),  // "Measured Storyteller"
            // Never quoted: the game reports what he says through "a mechanical translator slung
            // around his neck", so each report gets a translator line. "Ambassador" (capitalized)
            // never appears in the text, so no quote is ever attributed to him by name.
            CharacterVoice(characterID: "ambassador", names: ["Ambassador"],
                           fishVoiceID: "50b20b6a22e04352877c0c01b194c1aa",  // "IBM-7094": monotone computer
                           reportedSpeech: [
                               ReportedSpeech("wheezes loudly",
                                              says: "[wheezing] Greetings, ensign. A gift from Blow'k-bibben-Gordo."),
                               ReportedSpeech("introduces himself as Br'gun-te'elkner-ipg'nun",
                                              says: "Greetings. I am Br'gun-te'elkner-ipg'nun."),
                               ReportedSpeech("asks if you are performing some sort of religious ceremony",
                                              says: "Are you performing some sort of religious ceremony?"),
                               ReportedSpeech("inquires whether you are interested in a game of Bocci",
                                              says: "Would you be interested in a game of Bocci?"),
                               ReportedSpeech("recites a plea for coexistence between your races",
                                              says: "[solemnly] Let our two great races live side by side, in peace."),
                               ReportedSpeech("asks where Admiral Smithers can be found",
                                              says: "Where can Admiral Smithers be found?"),
                               ReportedSpeech("remarks that all humans look alike to him",
                                              says: "Forgive me. All humans look alike to me."),
                               ReportedSpeech("offers you a bit of celery",
                                              says: "Would you care for a bit of celery?"),
                               ReportedSpeech("grunts a polite farewell",
                                              says: "[grunting] Farewell, ensign."),
                               ReportedSpeech("squawks frantically",
                                              says: "[squawking frantically] Squawk! Squawk!"),
                               ReportedSpeech("whimpers and slaps your wrist",
                                              says: "[whimpering] Please, not the translator!"),
                           ]),
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
        if let speed = DotEnv.value(for: "FISH_SPEED_NARRATOR", environment: environment, envFile: envFile)
            .flatMap(Double.init), speed > 0 {
            cast.narratorSpeed = speed
        }
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

    /// One piece of speech in a paragraph: a quote, or a phrase the game uses to report speech.
    private struct Speech {
        let range: Range<String.Index>
        let voice: CharacterVoice
        /// The spoken words, without delivery tags.
        let words: String
        /// For quotes, the delivery taken from the verbs around them. Reported speech carries its
        /// own tags in `taggedLine`.
        let direction: String?
        let taggedLine: String?
    }

    private static func script(forParagraph paragraph: String, voices: [CharacterVoice]) -> TurnScript {
        let speech = (quotedSpeech(in: paragraph, voices: voices) + reportedSpeech(in: paragraph, voices: voices))
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
        guard !speech.isEmpty else { return TurnScript(narration: paragraph, lines: []) }

        var narration = ""
        var narrated = paragraph.startIndex
        var lines: [SpokenLine] = []
        var lastDirection: String?
        for piece in speech where piece.range.lowerBound >= narrated {
            narration += paragraph[narrated..<piece.range.lowerBound] + "[\(piece.voice.names[0]) speaks]"
            narrated = piece.range.upperBound

            if var last = lines.last, last.characterID == piece.voice.characterID {
                // Same speaker in the same breath: keep a quote's tag only if the delivery changes.
                let tagged = piece.taggedLine
                    ?? (piece.direction != nil && piece.direction != lastDirection
                        ? "[\(piece.direction!)] \(piece.words)" : piece.words)
                last.text += " " + piece.words
                last.ttsText += " " + tagged
                lines[lines.count - 1] = last
            } else {
                lastDirection = nil
                let tagged = piece.taggedLine ?? ((piece.direction.map { "[\($0)] " } ?? "") + piece.words)
                lines.append(SpokenLine(characterID: piece.voice.characterID, text: piece.words, ttsText: tagged))
            }
            if piece.direction != nil { lastDirection = piece.direction }
        }
        narration += paragraph[narrated...]
        return TurnScript(narration: narration, lines: lines)
    }

    /// Quotes, each given to the nearest voiced name before it, else after it.
    private static func quotedSpeech(in paragraph: String, voices: [CharacterVoice]) -> [Speech] {
        let quotes = paragraph.matches(of: /"([^"]+)"/)
        let quoteRanges = quotes.map(\.range)
        let mentions = voices.flatMap { voice in
            voice.names.flatMap { name in
                paragraph.ranges(of: wordPattern(name)).map { Mention(voice: voice, range: $0) }
            }
        }.filter { mention in !quoteRanges.contains { $0.overlaps(mention.range) } }
        guard !mentions.isEmpty else { return [] }

        var speech: [Speech] = []
        for (index, quote) in quotes.enumerated() {
            let previousEnd = index > 0 ? quotes[index - 1].range.upperBound : paragraph.startIndex
            let lead = paragraph[previousEnd..<quote.range.lowerBound]
            guard !introducesWrittenText(lead) else { continue }
            let before = mentions.filter { $0.range.upperBound <= quote.range.lowerBound }
                .max { $0.range.lowerBound < $1.range.lowerBound }
            let after = mentions.filter { $0.range.lowerBound >= quote.range.upperBound }
                .min { $0.range.lowerBound < $1.range.lowerBound }
                .flatMap { mention -> Mention? in
                    // Right after the quote ('"Hi!" says Floyd'), with no other quote in between.
                    let between = paragraph[quote.range.upperBound..<mention.range.lowerBound]
                    guard between.count <= 40, !between.contains("\"") else { return nil }
                    let around = paragraph[quote.range.upperBound..<(paragraph.index(
                        mention.range.upperBound, offsetBy: 20, limitedBy: paragraph.endIndex) ?? paragraph.endIndex)]
                    return speaksAfterQuote(around) ? mention : nil
                }
            guard let speaker = (before ?? after)?.voice else { continue }

            let nextStart = index + 1 < quotes.count ? quotes[index + 1].range.lowerBound : paragraph.endIndex
            // The sentence right after the quote ("he sneers.") says how it was delivered, else the
            // one right before it ("Blather shouts", "Blather's sneer softens a bit.").
            let direction = direction(in: firstSentence(paragraph[quote.range.upperBound..<nextStart]))
                ?? direction(in: lastSentence(lead))
            speech.append(Speech(range: quote.range, voice: speaker,
                                 words: String(quote.output.1).trimmingCharacters(in: .whitespaces),
                                 direction: direction, taggedLine: nil))
        }
        return speech
    }

    /// Phrases the game uses to report a character's speech ("asks where Admiral Smithers can be
    /// found"), outside any quotes.
    private static func reportedSpeech(in paragraph: String, voices: [CharacterVoice]) -> [Speech] {
        let quoteRanges = paragraph.matches(of: /"([^"]+)"/).map(\.range)
        return voices.flatMap { voice in
            voice.reportedSpeech.flatMap { reported in
                paragraph.ranges(of: reported.phrase)
                    .filter { range in !quoteRanges.contains { $0.overlaps(range) } }
                    .map { range in
                        Speech(range: range, voice: voice, words: withoutTags(reported.line),
                               direction: nil, taggedLine: reported.line)
                    }
            }
        }
    }

    private static func withoutTags(_ line: String) -> String {
        line.replacing(/\[[^\]]*\]/, with: "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Words just before a quote that mark it as writing, not speech: `labelled "Spam and Egz"`.
    private static func introducesWrittenText(_ lead: Substring) -> Bool {
        let nearby = lead.suffix(30).lowercased()
        if ["label", "reads", "embossed", "marked", "painted", "written", "inscribed", "engraved",
            "titled", "the word", "sign"].contains(where: { nearby.contains($0) }) { return true }
        // Things that "say" something are showing text: 'the button ... says "ASID."'
        let sentence = lastSentence(lead).lowercased()
        return sentence.contains("says")
            && ["button", "plaque", "screen", "display", "panel", "card", "note", "sticker", "door",
                "machine", "dial", "brochure", "sheet", "paper", "slip"].contains { sentence.contains($0) }
    }

    /// Whether a name after a quote is its speaker: only with a speech verb close by, as in
    /// '"Hi!" says Floyd' or '"Hi!" Floyd squeals.' A mention like 'Floyd follows you.' isn't.
    private static func speaksAfterQuote(_ between: Substring) -> Bool {
        let nearby = between.lowercased()
        return ["say", "said", "ask", "shout", "yell", "exclaim", "repl", "whisper", "cry", "cries", "sing",
                "sang", "announc", "add", "call", "squeal", "giggl", "mutter", "bellow", "sneer", "chirp",
                "grumbl", "complain", "wheez", "remark", "inquir", "beg", "plead", "explain", "tell", "insist"]
            .contains { nearby.contains($0) }
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
