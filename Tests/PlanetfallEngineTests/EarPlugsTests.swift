import Foundation
import Testing
@testable import PlanetfallEngine

struct EarPlugsCommandTests {
    @Test(arguments: ["plug your ears", "Plug ears", "cover your ears!", "Put my fingers in my ears.",
                      "stick fingers in ears", "block your ears", "jam your fingers into your ears",
                      "plug up your ears", "put in earplugs", "cover both ears"])
    func plugs(_ line: String) {
        #expect(EarPlugs.command(in: line) == .plug)
    }

    @Test(arguments: ["unplug your ears", "take your fingers out of your ears", "remove fingers from ears",
                      "uncover ears", "stop covering your ears", "pull my fingers out of my ears", "take out the earplugs"])
    func unplugs(_ line: String) {
        #expect(EarPlugs.command(in: line) == .unplug)
    }

    @Test(arguments: ["examine ears", "listen", "plug", "wait", "take brush", "ears"])
    func leavesOtherCommandsToTheGame(_ line: String) {
        #expect(EarPlugs.command(in: line) == nil)
    }

    @Test func voiceInputRecognizesAppCommands() {
        #expect(AppCommands.recognizes("Plug your ears."))
        #expect(AppCommands.recognizes("take a nap"))
        #expect(!AppCommands.recognizes("open the door"))
    }
}

@MainActor
@Suite(.enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
struct EarPlugsGameTests {
    @Test func pluggingYourEarsIsHandledByTheAppAndTakesNoGameTime() async throws {
        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!, storyURL: GameLocator.storyURL()!,
                                  savesDirectory: FileManager.default.temporaryDirectory, randomSeed: 8)
        var events: [String] = []
        var turns: [GameTurn] = []
        session.addObserver { event in
            switch event {
            case .turn(let turn): turns.append(turn); events.append("turn")
            case .command(let line): events.append("command:\(line)")
            default: break
            }
        }
        try session.start()
        defer { session.stop() }
        for _ in 0..<100 where turns.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        let movesBefore = session.status?.moves
        events = []

        session.send("Plug your ears!")
        #expect(events == ["command:Plug your ears!", "turn"])
        #expect(session.earsPlugged)
        #expect(turns.last?.text.contains("fingers firmly into your ears") == true)
        session.send("cover ears")
        #expect(turns.last?.text.contains("already plugged") == true)

        // The game never saw those: a real command still works, and the clock moved only for it.
        let target = turns.count + 1
        session.send("wait")
        for _ in 0..<100 where turns.count < target { try await Task.sleep(for: .milliseconds(20)) }
        #expect(turns.last?.text.contains("Time passes") == true)
        #expect(session.status?.moves != movesBefore)

        session.send("take your fingers out of your ears")
        #expect(!session.earsPlugged)
        #expect(turns.last?.text.contains("comes rushing back") == true)
        #expect(session.transcript.filter { if case .command = $0 { true } else { false } }.count == 4)
    }
}
