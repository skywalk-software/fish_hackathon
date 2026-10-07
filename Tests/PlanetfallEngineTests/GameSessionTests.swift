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
}
