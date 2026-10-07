import Foundation
import Testing
@testable import PlanetfallEngine

struct DialogueExtractorTests {
    private let voices = VoiceCast.defaults.characters

    private func blather(_ text: String) -> [SpokenLine] {
        DialogueExtractor.lines(in: text, voices: voices)
    }

    /// Blather's opening, as dfrotz prints it: one paragraph wrapped at 255 columns.
    @Test func joinsWrappedParagraphAndMergesQuotesInOneBreath() {
        let turn = """
            Ensign First Class Blather swaggers in. He studies your work with half-closed eyes. "You call this polishing, Ensign Seventh Class?" he sneers. "We have a position for an Ensign Ninth Class in the toilet-scrubbing division, you know. Thirty demerits." He
            glares at you, his arms crossed.
            """
        #expect(blather(turn) == [SpokenLine(
            characterID: "blather",
            text: "You call this polishing, Ensign Seventh Class? We have a position for an Ensign Ninth Class in the toilet-scrubbing division, you know. Thirty demerits.",
            ttsText: "[sneering] You call this polishing, Ensign Seventh Class? We have a position for an Ensign Ninth Class in the toilet-scrubbing division, you know. Thirty demerits.")])
    }

    @Test(arguments: [
        // Name before the quote.
        (#"Blather shouts "Speak when you're spoken to, Ensign Seventh Class!" He breaks three pencil points in a frenzied rush to give you more demerits."#,
         "[shouting] Speak when you're spoken to, Ensign Seventh Class!"),
        // Name after the quote.
        (#""I said to return to your post, Ensign Seventh Class!" bellows Blather, turning a deepening shade of crimson."#,
         "[shouting] I said to return to your post, Ensign Seventh Class!"),
        // "softens" wins over "sneer".
        (#"Blather's sneer softens a bit. "First right thing you've done today. Only five demerits.""#,
         "[grudgingly] First right thing you've done today. Only five demerits."),
        (#"Ensign Blather, his uniform immaculate, enters and notices you are away from your post. "Twenty demerits, Ensign Seventh Class!" bellows Blather. "Forty if you're not back on Deck Nine in five seconds!" He curls his face into a hideous mask of disgust at your unbelievable negligence."#,
         "[shouting] Twenty demerits, Ensign Seventh Class! Forty if you're not back on Deck Nine in five seconds!"),
    ])
    func attributesEveryBlatherLineInTheGame(paragraph: String, expected: String) {
        let lines = blather(paragraph)
        #expect(lines.map(\.characterID) == ["blather"])
        #expect(lines.first?.ttsText == expected)
    }

    @Test func ignoresQuotesInParagraphsThatDontNameAVoicedCharacter() {
        let turn = """
            Time passes...

            I don't know the word "sorry."

            Blather, adding fifty more demerits for good measure, moves off in search of more young ensigns to terrorize.
            """
        #expect(blather(turn).isEmpty)
    }

    @Test func eachParagraphIsItsOwnLine() {
        let turn = """
            Blather shouts "Speak when you're spoken to!"

            The loudspeaker crackles: "All hands to stations."

            "Twenty demerits!" bellows Blather.
            """
        #expect(blather(turn).map(\.text) == ["Speak when you're spoken to!", "Twenty demerits!"])
    }

    @Test func picksTheNearestNamedSpeaker() {
        let lines = DialogueExtractor.lines(in: #""Hi!" says Floyd. Blather shouts "Quiet, robot!""#, voices: voices)
        #expect(lines.map(\.characterID) == ["floyd", "blather"])
        #expect(lines.map(\.ttsText) == ["Hi!", "[shouting] Quiet, robot!"])
    }

    /// The real game: with seed 8, Blather swaggers in on the fourth turn.
    @MainActor
    @Test(.enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
    func findsBlatherInARealTurn() async throws {
        let saves = FileManager.default.temporaryDirectory.appendingPathComponent("planetfall-voice-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: saves) }
        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!, storyURL: GameLocator.storyURL()!,
                                  savesDirectory: saves, randomSeed: 8)
        var lines: [SpokenLine] = []
        var turns = 0
        session.addObserver { event in
            guard case .turn(let turn) = event else { return }
            turns += 1
            lines += DialogueExtractor.lines(in: turn.text, voices: VoiceCast.defaults.characters)
        }
        try session.start()
        defer { session.stop() }
        for expected in 1...5 {
            for _ in 0..<100 where turns < expected { try await Task.sleep(for: .milliseconds(50)) }
            if expected < 5 { session.send("wait") }
        }
        #expect(lines.count == 1)
        #expect(lines.first?.ttsText.hasPrefix("[sneering] You call this polishing, Ensign Seventh Class?") == true)
    }
}

struct TurnScriptTests {
    private let voices = VoiceCast.defaults.characters

    @Test func narrationKeepsTheSceneAndMarksCharacterLines() {
        let turn = """
            Ensign First Class Blather swaggers in. He studies your work with half-closed eyes. "You call this polishing, Ensign Seventh Class?" he sneers. "We have a position for an Ensign Ninth Class in the toilet-scrubbing division, you know. Thirty demerits." He
            glares at you, his arms crossed.
            """
        let script = DialogueExtractor.script(for: turn, voices: voices)
        #expect(script.narration == "Ensign First Class Blather swaggers in. He studies your work with half-closed eyes. [Blather speaks] he sneers. [Blather speaks] He glares at you, his arms crossed.")
        #expect(script.lines.count == 1)
    }

    @Test func turnsWithoutDialogueAreAllNarration() {
        let turn = "Deck Nine\nThis is a featureless corridor.\n\nThe escape pod bulkhead is closed."
        let script = DialogueExtractor.script(for: turn, voices: voices)
        #expect(script.narration == "Deck Nine This is a featureless corridor.\n\nThe escape pod bulkhead is closed.")
        #expect(script.lines.isEmpty)
    }

    @Test func signsAndLabelsStayWithTheNarrator() {
        let turn = #"Floyd hands you a card embossed "Loowur Elavaatur Akses Kard." Floyd grins impishly. "Giving up, huh?""#
        let script = DialogueExtractor.script(for: turn, voices: voices)
        #expect(script.lines.map(\.ttsText) == ["[playful] Giving up, huh?"])
        #expect(script.narration.contains(#""Loowur Elavaatur Akses Kard.""#))
        #expect(script.narration.hasSuffix("Floyd grins impishly. [Floyd speaks]"))
    }

    @Test(arguments: [
        (#"Floyd giggles and pushes you away. "You're tickling Floyd!" He clutches at his side panels, laughing hysterically."#,
         "floyd", "[laughing] You're tickling Floyd!"),
        (#"Floyd looks slightly embarrassed. "You know me and my sense of direction." Then he looks up at you with wide, trusting eyes. "Tell Floyd a story?""#,
         "floyd", "You know me and my sense of direction. Tell Floyd a story?"),
        (#"As other cryo-units in the chambers beyond begin opening, the woman turns to you, bows gracefully, and speaks in a beautiful, lilting voice. "I am Veldina, leader of Resida.""#,
         "veldina", "[gentle] I am Veldina, leader of Resida."),
    ])
    func voicesTheOtherCharacters(paragraph: String, characterID: String, expected: String) {
        let lines = DialogueExtractor.lines(in: paragraph, voices: voices)
        #expect(lines.map(\.characterID) == [characterID])
        #expect(lines.first?.ttsText == expected)
    }
}

struct VoiceCastTests {
    @Test func envFileOverridesAnyVoice() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("voice-env-\(UUID().uuidString)")
        try "FISH_VOICE_BLATHER=my-own-arnold\nFISH_VOICE_NARRATOR=deep-narrator\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let cast = VoiceCast.load(environment: ["FISH_VOICE_SIDEKICK": "from-env"], envFile: file)
        #expect(cast.characters.first { $0.characterID == "blather" }?.fishVoiceID == "my-own-arnold")
        #expect(cast.characters.first { $0.characterID == "floyd" }?.fishVoiceID == VoiceCast.defaults.characters[1].fishVoiceID)
        #expect(cast.narratorVoiceID == "deep-narrator")
        #expect(cast.sidekickVoiceID == "from-env")
        #expect(VoiceCast.load(environment: [:], envFile: file.appendingPathExtension("missing")) == VoiceCast.defaults)
    }

    @Test func blatherIsArnold() {
        #expect(VoiceCast.defaults.characters.first?.characterID == "blather")
        #expect(VoiceCast.defaults.characters.first?.fishVoiceID == "546972d2053c481d86fe4449a1b54e27")
    }
}

struct NarratorTests {
    private func sentences(_ deltas: [String]) -> [String] {
        var filter = NarrationFilter()
        return deltas.flatMap { filter.feed($0) } + filter.finish()
    }

    @Test func streamsCompleteSentencesAndJoinsShortOnes() {
        #expect(sentences(["You step into a narrow ", "corridor that curves to starboard. A gang", "way leads up."])
            == ["You step into a narrow corridor that curves to starboard.", "A gangway leads up."])
        #expect(sentences(["Got it. ", "The brush is yours now, for better or worse."])
            == ["Got it. The brush is yours now, for better or worse."])
        #expect(sentences(["Time passes..."]) == ["Time passes..."])
    }

    @Test func skipMeansSilence() {
        #expect(sentences(["SK", "IP"]).isEmpty)
        #expect(sentences([" SKIP\n"]).isEmpty)
        #expect(sentences(["S", "ilence settles over Deck Nine."]) == ["Silence settles over Deck Nine."])
    }

    @Test func buildsAStreamingOpusRequestWithCachedInstructions() throws {
        let context = NarrationContext(location: "Deck Nine", command: "wait",
                                       output: "Blather swaggers in. [Blather speaks]", previousNarration: ["You scrub."])
        let request = try Narrator(apiKey: "test-key").makeRequest(context: context)
        #expect(request.url == URL(string: "https://api.anthropic.com/v1/messages"))
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["stream"] as? Bool == true)
        #expect(body["fallbacks"] as? String == "default")
        #expect((body["output_config"] as? [String: String]) == ["effort": "low"])
        let system = try #require(body["system"] as? [[String: Any]])
        #expect(system.first?["text"] as? String == Narrator.systemPrompt)
        #expect((system.first?["cache_control"] as? [String: String]) == ["type": "ephemeral"])
        let messages = try #require(body["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? String)
        #expect(content.contains("Player's command: > wait"))
        #expect(content.contains("<game_output>\nBlather swaggers in. [Blather speaks]\n</game_output>"))
        #expect(content.contains("- You scrub."))
    }

    /// Calls the real API. Opt in: ANTHROPIC_LIVE_TESTS=1 swift test --filter narratesARealTurn
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_LIVE_TESTS"] == "1" && AnthropicAPIKey.load() != nil))
    func narratesARealTurn() async throws {
        let turn = """
            Ensign First Class Blather swaggers in. He studies your work with half-closed eyes. "You call this polishing, Ensign Seventh Class?" he sneers. "We have a position for an Ensign Ninth Class in the toilet-scrubbing division, you know. Thirty demerits." He glares at you, his arms crossed.
            """
        let script = DialogueExtractor.script(for: turn, voices: VoiceCast.defaults.characters)
        let narrator = Narrator(apiKey: try #require(AnthropicAPIKey.load()))
        let start = ContinuousClock.now
        var firstAfter: Duration?
        var sentences: [String] = []
        for try await sentence in narrator.sentences(for: NarrationContext(
            location: "Deck Nine", command: "wait", output: script.narration, previousNarration: [])) {
            if firstAfter == nil { firstAfter = ContinuousClock.now - start }
            sentences.append(sentence)
        }
        let narration = sentences.joined(separator: " ")
        print("first sentence after \(firstAfter ?? .zero): \(narration)")
        #expect(narration.contains("Blather"))
        #expect(!narration.contains("polishing"))  // Blather says that himself
        #expect(!narration.contains("[") && !narration.contains("\""))
    }
}

struct FishTextToSpeechTests {
    @Test func requestsStreamingPCMInTheCharactersVoice() throws {
        let request = FishTextToSpeech(apiKey: "test-key").makeRequest(text: "[shouting] Twenty demerits!", voiceID: "voice-1")
        #expect(request.url == FishTextToSpeech.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "model") == "s2.1-pro-free")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["text"] as? String == "[shouting] Twenty demerits!")
        #expect(body["reference_id"] as? String == "voice-1")
        #expect(body["format"] as? String == "pcm")
        #expect(body["sample_rate"] as? Int == 24_000)
        #expect(body["latency"] as? String == "balanced")
    }

    @Test func readsFishErrorMessages() {
        #expect(FishTextToSpeech.errorMessage(in: Data(#"{"status":404,"message":"Model not found"}"#.utf8)) == "Model not found")
        #expect(FishTextToSpeech.errorMessage(in: Data("<html>".utf8)) == nil)
    }

    @Test func cacheRoundTripsByModelVoiceAndText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("voice-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = VoiceLineCache(directory: directory)
        cache.store(Data([1, 2, 3, 4]), text: "Hi", voiceID: "a", model: "m")
        #expect(cache.load(text: "Hi", voiceID: "a", model: "m") == Data([1, 2, 3, 4]))
        #expect(cache.load(text: "Hi", voiceID: "b", model: "m") == nil)
        #expect(cache.load(text: "Hi!", voiceID: "a", model: "m") == nil)
        #expect(cache.load(text: "Hi", voiceID: "a", model: "other") == nil)
    }

    /// Streams a line in every cast voice from the real API. Opt in: FISH_LIVE_TESTS=1 swift test
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FISH_LIVE_TESTS"] == "1" && FishAPIKey.load() != nil))
    func streamsEveryCastVoice() async throws {
        let speech = FishTextToSpeech(apiKey: try #require(FishAPIKey.load()))
        let cast = VoiceCast.load()
        let voices = [("narrator", cast.narratorVoiceID), ("SNARK-9", cast.sidekickVoiceID)]
            + cast.characters.map { ($0.characterID, $0.fishVoiceID) }
        for (role, voiceID) in voices {
            let start = ContinuousClock.now
            var firstChunkAfter: Duration?
            var audio = Data()
            for try await chunk in speech.stream("Twenty demerits, Ensign Seventh Class!", voiceID: voiceID) {
                if firstChunkAfter == nil { firstChunkAfter = ContinuousClock.now - start }
                audio.append(chunk)
            }
            let seconds = Double(audio.count) / 2 / Double(FishTextToSpeech.sampleRate)
            print("\(role): first chunk after \(firstChunkAfter ?? .zero), \(seconds) s of audio")
            #expect(seconds > 1, "\(role)")
            #expect(audio.count.isMultiple(of: 2), "\(role)")
        }
    }
}
