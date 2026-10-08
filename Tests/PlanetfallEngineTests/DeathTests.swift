import Foundation
import Testing
@testable import PlanetfallEngine

@MainActor
@Suite(.enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
struct DeathTests {
    @Test func dyingMarksThePlayerDeadUntilTheyRestart() async throws {
        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!, storyURL: GameLocator.storyURL()!,
                                  savesDirectory: FileManager.default.temporaryDirectory, randomSeed: 8)
        var turns: [GameTurn] = []
        session.addObserver { if case .turn(let turn) = $0 { turns.append(turn) } }
        try session.start()
        defer { session.stop() }
        func play(_ command: String) async throws {
            let target = turns.count + 1
            session.send(command)
            for _ in 0..<300 where turns.count < target { try await Task.sleep(for: .milliseconds(20)) }
        }
        for _ in 0..<100 where turns.isEmpty { try await Task.sleep(for: .milliseconds(20)) }

        try await play("cheat: brig")  // locked in the brig as the ship blows up
        #expect(!session.isDead)
        for _ in 0..<12 where !session.isDead { try await play("wait") }
        #expect(session.isDead)
        #expect(turns.last?.text.contains("You have died") == true)

        try await play("restart")
        #expect(!session.isDead)
        #expect(session.status?.location == "Deck Nine")
    }
}
