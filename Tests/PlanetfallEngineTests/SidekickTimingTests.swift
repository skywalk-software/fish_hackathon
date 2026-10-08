import Foundation
import Testing
@testable import PlanetfallEngine

/// SNARK-9's pacing against a real game, with Claude replaced by a stub that counts requests.
@MainActor
@Suite(.serialized, .enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
struct SidekickTimingTests {
    private func sse(_ text: String) -> String {
        """
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\(text)"}}

        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

        """
    }

    /// A started seed-8 game, its sidekick (stubbed), and a count of visible turns.
    private func setUp(reply: String) async throws -> (GameSession, Sidekick, Stub, () -> Int) {
        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!, storyURL: GameLocator.storyURL()!,
                                  savesDirectory: FileManager.default.temporaryDirectory, randomSeed: 8)
        var turns = 0
        session.addObserver { if case .turn = $0 { turns += 1 } }
        let stub = Stub(body: sse(reply))
        let sidekick = Sidekick(session: session, commentator: Commentator(apiKey: "sk-test", urlSession: stub.session))
        sidekick.isEnabled = true
        sidekick.commentDelay = .milliseconds(400)
        try session.start()
        for _ in 0..<100 where turns < 1 { try await Task.sleep(for: .milliseconds(20)) }
        return (session, sidekick, stub, { turns })
    }

    private func waitForTurn(_ count: () -> Int, after before: Int) async throws {
        for _ in 0..<100 where count() <= before { try await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func quickSuccessiveCommandsCostOneRequest() async throws {
        let (session, sidekick, stub, turns) = try await setUp(reply: "[deadpan] Riveting.")
        defer { session.stop() }
        for _ in 0..<3 {
            let before = turns()
            session.send("wait")
            try await waitForTurn(turns, after: before)
        }
        try await Task.sleep(for: .milliseconds(900))
        #expect(stub.requestCount == 1)  // only the last turn, once the player paused
        #expect(sidekick.line == "Riveting.")  // no voice: shown as soon as it's written, tag-free
    }

    @Test func theCaptionBlanksOnACommandAndStaysBlankOnAPass() async throws {
        let (session, sidekick, stub, turns) = try await setUp(reply: "[deadpan] Riveting.")
        defer { session.stop() }
        var before = turns()
        session.send("wait")
        try await waitForTurn(turns, after: before)
        try await Task.sleep(for: .milliseconds(900))
        #expect(sidekick.line == "Riveting.")

        stub.body = sse("PASS")
        before = turns()
        session.send("wait")
        #expect(sidekick.line.isEmpty)  // blank the moment the player sends a command
        try await waitForTurn(turns, after: before)
        try await Task.sleep(for: .milliseconds(900))
        #expect(stub.requestCount == 2)
        #expect(sidekick.line.isEmpty)  // SNARK-9 passed, so the caption stays blank
    }

    @Test func withAVoiceTheCaptionWaitsForSpeechAndTheRequestWaitsForNarration() async throws {
        let (session, sidekick, stub, turns) = try await setUp(reply: "[deadpan] Riveting.")
        defer { session.stop() }
        sidekick.captionWaitsForVoice = true
        var narrationDone = false
        sidekick.readyToComment = {
            while !narrationDone { try? await Task.sleep(for: .milliseconds(20)) }
        }
        var spoken: [String] = []
        sidekick.onLineFinished { spoken.append($0) }

        let before = turns()
        session.send("wait")
        try await waitForTurn(turns, after: before)
        try await Task.sleep(for: .milliseconds(700))
        #expect(stub.requestCount == 0)  // still narrating: no request yet

        narrationDone = true
        try await Task.sleep(for: .milliseconds(400))
        #expect(stub.requestCount == 1)
        #expect(spoken == ["[deadpan] Riveting."])  // the voice gets the tag
        #expect(sidekick.line.isEmpty)  // but the caption waits for the voice to start
        sidekick.revealCaption()
        #expect(sidekick.line == "Riveting.")
    }
}
