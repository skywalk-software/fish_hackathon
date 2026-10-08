import Foundation
import Testing
@testable import PlanetfallEngine

struct NapRuleTests {
    @Test func recognizesNapCommands() {
        #expect(Nap.isNapCommand("sleep"))
        #expect(Nap.isNapCommand("  Take a nap. "))
        #expect(Nap.isNapCommand("doze off"))
        #expect(!Nap.isNapCommand("wait"))
        #expect(!Nap.isNapCommand("sleep on the floor"))
    }

    @Test func onlyOnDeckNineBeforeTheExplosion() {
        #expect(Nap.applies(location: "Deck Nine", storyEvents: [], playerHolder: "Deck Nine"))
        #expect(Nap.applies(location: "Deck Nine", storyEvents: [], playerHolder: nil))
        #expect(!Nap.applies(location: "Deck Nine", storyEvents: ["explosion"], playerHolder: "Deck Nine"))
        #expect(!Nap.applies(location: "Gangway", storyEvents: [], playerHolder: "Gangway"))
    }
}

/// Real games through dfrotz with fixed random seeds. Skipped without dfrotz or the story file.
@MainActor
@Suite(.serialized, .enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
struct NapGameTests {
    /// A session that records every event it emits.
    private final class Recorder {
        var events: [String] = []
        var turns: [GameTurn] = []
    }

    private func start(seed: Int) async throws -> (GameSession, Recorder) {
        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!, storyURL: GameLocator.storyURL()!,
                                  savesDirectory: FileManager.default.temporaryDirectory, randomSeed: seed)
        let recorder = Recorder()
        session.addObserver { event in
            switch event {
            case .turn(let turn): recorder.turns.append(turn); recorder.events.append("turn")
            case .command(let line): recorder.events.append("command:\(line)")
            case .achievementUnlocked(let a): recorder.events.append("achievement:\(a.id)")
            case .ended: recorder.events.append("ended")
            }
        }
        try session.start()
        for _ in 0..<100 where recorder.turns.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        return (session, recorder)
    }

    /// Sends a command and waits for the next visible turn (a whole nap counts as one).
    private func play(_ command: String, _ session: GameSession, _ recorder: Recorder) async throws -> GameTurn {
        let target = recorder.turns.count + 1
        session.send(command)
        for _ in 0..<250 where recorder.turns.count < target { try await Task.sleep(for: .milliseconds(20)) }
        return try #require(recorder.turns.last)
    }

    @Test func sleepsThroughBlatherAndWakesAtTheExplosion() async throws {
        let (session, recorder) = try await start(seed: 8)  // Blather visits on turn 4, explosion on turn 9
        defer { session.stop() }
        let transcriptBefore = session.transcript.count
        recorder.events = []

        let turn = try await play("sleep", session, recorder)
        // One command and one turn for the whole nap: nothing else reached observers.
        #expect(recorder.events == ["command:sleep", "turn"])
        #expect(session.transcript.count == transcriptBefore + 2)
        #expect(turn.text.hasPrefix("You lean on your trusty scrub brush"))
        #expect(turn.text.contains("bellowing about demerits"))
        #expect(turn.text.contains("You wake with a start!"))
        #expect(turn.text.contains("A massive explosion rocks the ship"))
        #expect(!turn.text.contains("Time passes"))
        #expect(session.storyEvents == ["explosion"])
        #expect(!session.isNapping)

        // After the explosion, SLEEP is the game's own again.
        let after = try await play("sleep", session, recorder)
        #expect(after.text.contains("You're not tired!"))
    }

    @Test func theAmbassadorWakesYouBeforeTheExplosion() async throws {
        let (session, recorder) = try await start(seed: 2)  // ambassador on turn 4, explosion on turn 8
        defer { session.stop() }
        let turn = try await play("take a nap", session, recorder)
        #expect(turn.text.contains("A loud, wet wheezing wakes you."))
        #expect(turn.text.contains("The alien ambassador from the planet Blow'k-bibben-Gordo"))
        #expect(!turn.text.contains("explosion"))
        #expect(session.storyEvents.isEmpty)
        #expect(session.presentCharacters.map(\.id) == ["ambassador"])
    }

    @Test func sleepElsewhereGoesToTheGame() async throws {
        let (session, recorder) = try await start(seed: 8)
        defer { session.stop() }
        _ = try await play("up", session, recorder)
        let turn = try await play("sleep", session, recorder)
        #expect(turn.text.contains("You're not tired!"))
    }

    @Test func snarkCommentsOnceForTheWholeNap() async throws {
        let (session, recorder) = try await start(seed: 8)
        defer { session.stop() }
        let urlSession = StubURLProtocol.session(statusCode: 200, body: "")
        let sidekick = Sidekick(session: session, commentator: Commentator(apiKey: "sk-test", urlSession: urlSession))
        sidekick.isEnabled = true
        StubURLProtocol.requestCount = 0

        _ = try await play("sleep", session, recorder)
        for _ in 0..<50 where StubURLProtocol.requestCount < 1 { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(StubURLProtocol.requestCount == 1)
    }
}
