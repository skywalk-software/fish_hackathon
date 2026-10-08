import Foundation
import Testing
@testable import PlanetfallEngine

@MainActor
struct AchievementStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "planetfall-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func earnsFromGameTextOnceAndRemembersAcrossLaunches() {
        let defaults = freshDefaults()
        let store = AchievementStore(defaults: defaults)
        #expect(store.earned.isEmpty)
        #expect(!store.isUnlocked(icon: "ensign"))
        #expect(store.isUnlocked(icon: "poster"))  // no achievement gates it

        let text = "Through the viewport of the pod you see the Feinstein dwindle as you head away."
        #expect(store.record(text).map(\.id) == ["escaped"])
        #expect(store.latestUnlock?.id == "escaped")
        #expect(store.isUnlocked(icon: "ensign"))
        #expect(store.record(text).isEmpty)  // only once

        let relaunched = AchievementStore(defaults: defaults)
        #expect(relaunched.earned.keys.sorted() == ["escaped"])
        #expect(relaunched.isUnlocked(icon: "ensign"))
        #expect(relaunched.latestUnlock == nil)  // no toast for old achievements

        relaunched.reset()
        #expect(AchievementStore(defaults: defaults).earned.isEmpty)
    }

    @Test func commentaryPromptAwardsWithoutScriptingTheLine() throws {
        let escaped = try #require(Achievement.with(id: "escaped"))
        let context = CommentaryContext(location: "Escape Pod", score: 3, moves: 4952, turnsPlayed: 14,
                                        recentOutput: "> wait\nThrough the viewport...", previousLines: [],
                                        newAchievements: [escaped])
        let message = Commentator.userMessage(context: context)
        #expect(message.contains("<achievement_unlocked>"))
        #expect(message.contains("Abandon Ship"))
        #expect(message.contains("Dock icon"))
        #expect(Commentator(apiKey: "sk-test").systemPrompt.contains("Never pass on an achievement turn"))

        let quiet = CommentaryContext(location: "Deck Nine", score: 0, moves: 4454,
                                      recentOutput: "> look", previousLines: [])
        #expect(!Commentator.userMessage(context: quiet).contains("achievement"))
    }

    @Test(.enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
    func escapingInThePodEarnsAbandonShipBeforeItsTurn() async throws {
        let saves = FileManager.default.temporaryDirectory
            .appendingPathComponent("planetfall-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: saves) }

        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!, storyURL: GameLocator.storyURL()!,
                                  savesDirectory: saves, randomSeed: 8)
        let store = AchievementStore(defaults: freshDefaults())
        session.achievements = store
        var log: [String] = []
        var turnCount = 0
        session.addObserver { event in
            switch event {
            case .achievementUnlocked(let achievement): log.append("achievement:\(achievement.id)")
            case .turn(let turn):
                turnCount += 1
                if turn.text.contains("Feinstein dwindle") { log.append("turn:escaped") }
            default: break
            }
        }
        try session.start()
        defer { session.stop() }

        func play(_ command: String) async throws {
            let target = turnCount + 1
            session.send(command)
            for _ in 0..<100 where turnCount < target { try await Task.sleep(for: .milliseconds(20)) }
            try #require(turnCount >= target)
        }
        for _ in 0..<100 where turnCount < 1 { try await Task.sleep(for: .milliseconds(20)) }

        for command in Array(repeating: "wait", count: 9) + ["west", "get in webbing"] {
            try await play(command)
        }
        #expect(!store.isUnlocked(icon: "ensign"))
        for _ in 0..<4 where !log.contains("turn:escaped") { try await play("wait") }

        // Announced just before the turn it happened on, so SNARK-9 can award it.
        #expect(log.suffix(2) == ["achievement:escaped", "turn:escaped"])
        #expect(store.isUnlocked(icon: "ensign"))
    }
}
