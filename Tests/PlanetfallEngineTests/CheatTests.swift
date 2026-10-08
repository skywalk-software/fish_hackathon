import Foundation
import Testing
@testable import PlanetfallEngine

struct CheatParsingTests {
    @Test func parsesCheatCommands() {
        #expect(Cheat.request(in: "cheat: pod") == .cheat(.pod))
        #expect(Cheat.request(in: "Cheat: Splash") == .cheat(.splash))
        #expect(Cheat.request(in: "cheat:explode") == .cheat(.explode))
        #expect(Cheat.request(in: "cheat brig") == .cheat(.brig))
        #expect(Cheat.request(in: "cheat: warp") == .unknown("warp"))
        #expect(Cheat.request(in: "cheat") == .unknown(""))
        #expect(Cheat.request(in: "cheater") == nil)
        // As speech-to-text writes them.
        #expect(Cheat.request(in: "Cheat, pod.") == .cheat(.pod))
        #expect(Cheat.request(in: "Cheat code splash") == .cheat(.splash))
        #expect(Cheat.request(in: "cheat brick") == .cheat(.brig))
        #expect(Cheat.request(in: "Cheat: explosion!") == .cheat(.explode))
        #expect(AppCommands.recognizes("Cheat, splash."))
        #expect(Cheat.request(in: "take brush") == nil)
    }
}

/// Each cheat replays against the real game. Skipped without dfrotz or the story file.
@MainActor
@Suite(.enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
struct CheatGameTests {
    /// Plays `line` in a fresh game (random seed 3, so the cheat's own seed matters) and
    /// returns the session plus everything observers saw after it.
    private func run(_ line: String) async throws -> (GameSession, [String], [GameTurn]) {
        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!, storyURL: GameLocator.storyURL()!,
                                  savesDirectory: FileManager.default.temporaryDirectory, randomSeed: 3)
        session.achievements = AchievementStore(defaults: UserDefaults(suiteName: "cheat-\(UUID().uuidString)")!)
        var events: [String] = []
        var turns: [GameTurn] = []
        session.addObserver { event in
            switch event {
            case .turn(let turn): turns.append(turn); events.append("turn")
            case .command(let command): events.append("command:\(command)")
            case .achievementUnlocked(let a): events.append("achievement:\(a.id)")
            case .ended: events.append("ended")
            }
        }
        try session.start()
        for _ in 0..<100 where turns.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        events = []
        let before = turns.count
        session.send(line)
        for _ in 0..<300 where turns.count == before { try await Task.sleep(for: .milliseconds(20)) }
        return (session, events, Array(turns.dropFirst(before)))
    }

    @Test func explodeLandsAtTheExplosion() async throws {
        let (session, events, turns) = try await run("cheat: explode")
        defer { session.stop() }
        #expect(events == ["command:cheat: explode", "turn"])  // the replay itself was hidden
        #expect(turns.last?.isCheat == true)
        #expect(turns.last?.text.contains("A massive explosion rocks the ship") == true)
        #expect(session.status?.location == "Deck Nine")
        #expect(session.storyEvents == ["explosion"])
        #expect(session.transcript.contains { $0 == .system(id: $0.id, text: "Cheat: explode. \(Cheat.explode.summary)") })
    }

    @Test func podLandsStrappedIntoTheWebbing() async throws {
        let (session, _, turns) = try await run("cheat: pod")
        defer { session.stop() }
        #expect(turns.last?.text.contains("safely cushioned within the web") == true)
        #expect(session.status?.location == "Escape Pod")
        #expect(session.playerHolder == "safety web")
        #expect(session.artTags == ["explosion", "webbing"])
    }

    @Test func splashLandsUnderwater() async throws {
        let (session, _, turns) = try await run("cheat: splash")
        defer { session.stop() }
        #expect(turns.last?.text.contains("turbulent waters") == true)
        #expect(session.status?.location == "Underwater")
        #expect(session.storyEvents.isEmpty)  // the explosion is long over
    }

    @Test func brigLandsInTheBrigWithoutEarningTheAchievement() async throws {
        let (session, events, turns) = try await run("cheat: brig")
        defer { session.stop() }
        #expect(turns.last?.text.contains("drags you to the Feinstein's brig") == true)
        #expect(session.status?.location == "Brig")
        #expect(!events.contains("achievement:brig"))
    }

    @Test func unknownCheatsListTheRealOnes() async throws {
        let (session, _, turns) = try await run("cheat: warp")
        defer { session.stop() }
        #expect(turns.last?.text.contains("cheat: splash") == true)
        #expect(session.status?.location == "Deck Nine")  // nothing restarted
    }
}
