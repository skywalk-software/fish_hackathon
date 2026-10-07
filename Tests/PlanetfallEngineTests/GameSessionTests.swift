import Foundation
import Testing
@testable import PlanetfallEngine

/// Plays a few real turns through dfrotz. Skipped when dfrotz or the story file is missing.
@MainActor
struct GameSessionTests {
    @Test(.enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
    func playsTurnsAndSaves() async throws {
        let saves = FileManager.default.temporaryDirectory
            .appendingPathComponent("planetfall-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: saves) }

        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!,
                                  storyURL: GameLocator.storyURL()!,
                                  savesDirectory: saves)
        var turns: [GameTurn] = []
        session.addObserver { event in
            if case .turn(let turn) = event { turns.append(turn) }
        }
        try session.start()
        defer { session.stop() }

        func waitForTurns(_ count: Int) async throws {
            for _ in 0..<100 where turns.count < count {
                try await Task.sleep(for: .milliseconds(50))
            }
            try #require(turns.count >= count)
        }

        try await waitForTurns(1)
        #expect(turns[0].text.contains("PLANETFALL"))
        #expect(session.status?.location == "Deck Nine")

        session.send("inventory")
        try await waitForTurns(2)
        #expect(turns[1].text.contains("You are carrying"))

        // The filename prompt has no ">", so it arrives via the quiet-period flush.
        session.send("save")
        try await waitForTurns(3)
        #expect(turns[2].prompt == .question)
        #expect(turns[2].text.contains("filename"))

        session.send("")
        try await waitForTurns(4)
        #expect(turns[3].prompt == .command)
        #expect(FileManager.default.fileExists(atPath: saves.appendingPathComponent("planetfall.qzl").path))
    }

    @Test(.enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
    func tracksCharactersComingAndGoing() async throws {
        let saves = FileManager.default.temporaryDirectory
            .appendingPathComponent("planetfall-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: saves) }

        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!,
                                  storyURL: GameLocator.storyURL()!,
                                  savesDirectory: saves,
                                  randomSeed: 8)
        var turnCount = 0
        session.addObserver { event in
            if case .turn = event { turnCount += 1 }
        }
        try session.start()
        defer { session.stop() }

        func play(_ command: String) async throws {
            let target = turnCount + 1
            session.send(command)
            for _ in 0..<100 where turnCount < target {
                try await Task.sleep(for: .milliseconds(20))
            }
            try #require(turnCount >= target)
        }
        for _ in 0..<100 where turnCount < 1 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(session.presentCharacters.isEmpty)

        // The game randomly sends Blather, the alien ambassador, or nobody to Deck Nine.
        // With seed 8, Blather swaggers in on the fourth turn.
        for _ in 0..<8 where session.presentCharacters.isEmpty {
            try await play("wait")
        }
        #expect(session.presentCharacters.map(\.id) == ["blather"])
        #expect(session.characterLocations["blather"] == "Deck Nine")
        // The narration shouldn't contain dfrotz's trace lines.
        #expect(!session.transcript.contains { entry in
            if case .narration(_, let text) = entry { text.contains("@move_obj") } else { false }
        })

        // Leaving the room hides him; he's still on Deck Nine.
        try await play("up")
        #expect(session.status?.location == "Gangway")
        #expect(session.presentCharacters.isEmpty)
        #expect(session.characterLocations["blather"] == "Deck Nine")
    }

    @Test(.enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
    func tracksTheExplosionAndForgetsItOnRestart() async throws {
        let saves = FileManager.default.temporaryDirectory
            .appendingPathComponent("planetfall-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: saves) }

        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!,
                                  storyURL: GameLocator.storyURL()!,
                                  savesDirectory: saves,
                                  randomSeed: 8)
        var turnCount = 0
        session.addObserver { event in
            if case .turn = event { turnCount += 1 }
        }
        try session.start()
        defer { session.stop() }

        func play(_ command: String) async throws {
            let target = turnCount + 1
            session.send(command)
            for _ in 0..<100 where turnCount < target {
                try await Task.sleep(for: .milliseconds(20))
            }
            try #require(turnCount >= target)
        }
        for _ in 0..<100 where turnCount < 1 { try await Task.sleep(for: .milliseconds(20)) }

        // With seed 8 the Feinstein starts exploding on the ninth turn.
        for _ in 0..<8 { try await play("wait") }
        #expect(session.storyEvents.isEmpty)
        try await play("wait")
        #expect(session.storyEvents == ["explosion"])

        // RESTART typed in the game asks to confirm, then prints the title banner again.
        try await play("restart")
        try await play("y")
        #expect(session.storyEvents.isEmpty)
        #expect(session.characterLocations.isEmpty)
    }

    @Test(.enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
    func tracksTheSafetyWebAndTheLaunch() async throws {
        let saves = FileManager.default.temporaryDirectory
            .appendingPathComponent("planetfall-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: saves) }

        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!,
                                  storyURL: GameLocator.storyURL()!,
                                  savesDirectory: saves,
                                  randomSeed: 8)
        var turns: [GameTurn] = []
        session.addObserver { event in
            if case .turn(let turn) = event { turns.append(turn) }
        }
        try session.start()
        defer { session.stop() }

        func play(_ command: String) async throws {
            let target = turns.count + 1
            session.send(command)
            for _ in 0..<100 where turns.count < target {
                try await Task.sleep(for: .milliseconds(20))
            }
            try #require(turns.count >= target)
        }
        for _ in 0..<100 where turns.isEmpty { try await Task.sleep(for: .milliseconds(20)) }

        for _ in 0..<9 { try await play("wait") }
        try await play("west")
        #expect(session.status?.location == "Escape Pod")
        #expect(session.artTags == ["explosion"])

        // Strapped in while the ship is still exploding around the pod.
        try await play("get in webbing")
        #expect(session.playerHolder == "safety web")
        #expect(session.artTags == ["explosion", "webbing"])

        // Once the pod is away from the Feinstein, the explosion phase is over.
        for _ in 0..<4 where !turns.contains(where: { $0.text.contains("Feinstein dwindle") }) {
            try await play("wait")
        }
        #expect(session.artTags == ["webbing"])

        // Standing up (any way out of the web) drops the webbing art.
        try await play("stand")
        #expect(session.playerHolder == "Escape Pod")
        #expect(session.artTags.isEmpty)
    }
}
