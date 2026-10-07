import Foundation
import Testing
@testable import PlanetfallEngine

/// Reads Planetfall's real dictionary. Skipped when the story file is missing.
@Suite(.enabled(if: GameVocabulary.planetfall != nil))
struct GameVocabularyTests {
    private let vocabulary = GameVocabulary.planetfall!

    @Test func readsTheParsersDictionary() {
        #expect(vocabulary.words.count > 600)
        #expect(vocabulary.separators == [".", ",", "\""])
        // Stored as the parser sees them: cut to six z-characters.
        #expect(vocabulary.words.contains("blathe"))
        #expect(vocabulary.words.contains("floyd"))
        #expect(vocabulary.words.contains("rat-a"))
        #expect(!vocabulary.words.contains { $0.hasPrefix("#") })
    }

    @Test(arguments: [
        "take brush. north",
        "examine blather",          // "blather" matches the stored "blathe"
        "floyd, hello",
        "Open the pod and take the kit",
        "type 384",                 // numbers are always fine
        "z",
    ])
    func acceptsCommandsTheParserKnows(command: String) {
        #expect(vocabulary.unknownWords(in: command).isEmpty, "\(command)")
    }

    @Test func listsWordsTheParserWouldReject() {
        #expect(vocabulary.unknownWords(in: "um please pick up the kit") == ["um", "please"])
        #expect(vocabulary.unknownWords(in: "take pizza, then pizza") == ["pizza"])
    }

    @Test func normalizeDropsPunctuationTheParserDoesntUse() {
        #expect(GameVocabulary.normalize("  north?  ") == "north")
        #expect(GameVocabulary.normalize("floyd, hello!") == "floyd, hello")
        #expect(vocabulary.unknownWords(in: GameVocabulary.normalize("where is floyd?")) == [])
    }

    @Test func encodesWordsLikeTheGame() {
        // Six z-characters: letters are 6...31 (a = 6), padding is 5, and punctuation shifts to
        // alphabet 2 with 5 ("-" is 28).
        let kit: [UInt8] = [16, 14, 25, 5, 5, 5]
        let ratAnt: [UInt8] = [23, 6, 25, 5, 28, 6]
        #expect(GameVocabulary.encode("kit") == kit)
        #expect(GameVocabulary.encode("blather") == GameVocabulary.encode("blathe"))
        #expect(GameVocabulary.encode("rat-ant") == ratAnt)
    }

    @Test func rejectsFilesThatArentVersion3Stories() {
        #expect(GameVocabulary(storyData: Data(repeating: 0, count: 100)) == nil)
        #expect(GameVocabulary(storyData: Data("not a story".utf8)) == nil)
    }
}

struct CommandInterpreterVocabularyTests {
    private let context = CommandContext(location: "Deck Nine", recentOutput: "A survey kit lies here.")

    @Test func sendsTheVocabularyAsACachedSystemBlock() throws {
        let request = try CommandInterpreter(apiKey: "k", vocabulary: ["kit", "take", "north"])
            .makeRequest(heard: "um grab the kid", context: context)
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let system = try #require(body["system"] as? [[String: Any]])
        #expect(system.count == 2)
        #expect(system[0]["text"] as? String == CommandInterpreter.systemPrompt)
        #expect(system[0]["cache_control"] == nil)
        let vocabulary = try #require(system[1]["text"] as? String)
        #expect(vocabulary.contains("<vocabulary>\nkit take north\n</vocabulary>"))
        #expect((system[1]["cache_control"] as? [String: String]) == ["type": "ephemeral"])
    }

    @Test func withoutAVocabularyTheRequestIsUnchanged() throws {
        let request = try CommandInterpreter(apiKey: "k").makeRequest(heard: "north", context: context)
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((body["system"] as? [[String: Any]])?.count == 1)
    }

    /// Calls the real API. Opt in: ANTHROPIC_LIVE_TESTS=1 swift test --filter cleanedCommandsUseTheGamesWords
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_LIVE_TESTS"] == "1"
                   && AnthropicAPIKey.load() != nil && GameVocabulary.planetfall != nil))
    func cleanedCommandsUseTheGamesWords() async throws {
        let vocabulary = try #require(GameVocabulary.planetfall)
        let interpreter = CommandInterpreter(apiKey: try #require(AnthropicAPIKey.load()), vocabulary: vocabulary.words)
        let context = CommandContext(location: "Deck Nine", recentOutput: """
            Deck Nine
            This is a featureless corridor similar to every other corridor on the ship. It curves away to \
            starboard, and a gangway leads up. To port is the entrance to one of the ship's primary escape pods. \
            The pod bulkhead is closed.
            A survey kit is lying here.
            """)
        for heard in ["um could you please grab the kid", "uh, let's go up the stairs", "open the pod door and then get inside"] {
            let command = try await interpreter.interpret(heard, context: context)
            print("\(heard) -> \(command)")
            #expect(!command.isEmpty, "\(heard)")
            #expect(vocabulary.unknownWords(in: GameVocabulary.normalize(command)).isEmpty, "\(heard) -> \(command)")
        }
    }
}

/// The session reports when the game is asking a question, so answers skip the vocabulary check.
@MainActor
@Suite(.enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
struct QuestionPromptTests {
    @Test func saveFilenamePromptIsAQuestion() async throws {
        let saves = FileManager.default.temporaryDirectory.appendingPathComponent("planetfall-prompt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: saves) }
        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!, storyURL: GameLocator.storyURL()!, savesDirectory: saves)
        var turns = 0
        session.addObserver { if case .turn = $0 { turns += 1 } }
        try session.start()
        defer { session.stop() }
        func waitForTurns(_ count: Int) async throws {
            for _ in 0..<100 where turns < count { try await Task.sleep(for: .milliseconds(50)) }
            try #require(turns >= count)
        }
        try await waitForTurns(1)
        #expect(session.commandContext().isAnsweringQuestion == false)
        session.send("save")
        try await waitForTurns(2)
        #expect(session.prompt == .question)
        #expect(session.commandContext().isAnsweringQuestion)
        session.send("")
        try await waitForTurns(3)
        #expect(session.commandContext().isAnsweringQuestion == false)
    }
}
