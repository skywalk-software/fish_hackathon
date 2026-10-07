import Foundation
import Testing
@testable import PlanetfallEngine

struct RedAlertTests {
    private let sampleRate = 24_000

    @Test func soundsFromTheExplosionUntilTheDangerIsOver() {
        let explosion = "A massive explosion rocks the ship. Echoes from the explosion resound deafeningly down the halls."
        #expect(!RedAlert.isSounding(after: "Time passes...", wasSounding: false))
        #expect(RedAlert.isSounding(after: explosion, wasSounding: false))
        #expect(RedAlert.isSounding(after: "More distant explosions!", wasSounding: true))
        #expect(!RedAlert.isSounding(after: "Through the viewport of the pod you see the Feinstein dwindle as you head away. Bursts of light dot its hull. Suddenly, a huge explosion blows the Feinstein into tiny pieces, sending the escape pod tumbling away!", wasSounding: true))
        #expect(!RedAlert.isSounding(after: "An enormous explosion tears the walls of the ship apart. If only you had made it to an escape pod...\n\n****  You have died  ****", wasSounding: true))
        #expect(!RedAlert.isSounding(after: "PLANETFALL\nInfocom interactive fiction - a science fiction story", wasSounding: true))
    }

    @Test func loopsSeamlesslyAtAComfortableLevel() {
        let pcm = RedAlert.loop(sampleRate: sampleRate).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
            .map(Int16.init(littleEndian:))
        #expect(pcm.count == Int(RedAlert.loopDuration * Double(sampleRate)))
        let peak = pcm.map { abs(Int($0)) }.max() ?? 0
        #expect(abs(Double(peak) / Double(Int16.max) - RedAlert.peakLevel) < 0.01)
        // Wrapping from the last sample to the first is no bigger a step than the loop's own.
        let biggestStep = zip(pcm, pcm.dropFirst()).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(abs(Int(pcm.last!) - Int(pcm.first!)) <= biggestStep)
        #expect(RedAlert.loop(sampleRate: sampleRate) == RedAlert.loop(sampleRate: sampleRate))
    }

    /// The real game with seed 8: the Feinstein starts exploding on the ninth wait.
    @MainActor
    @Test(.enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil),
          arguments: [
              // Stay on Deck Nine: the ship blows up with you on it on the 13th wait.
              (Array(repeating: "wait", count: 13), [9, 10, 11, 12]),
              // Get into the escape pod: it ejects, and the Feinstein blows apart behind you.
              (Array(repeating: "wait", count: 9) + ["west", "wait", "wait", "wait"], [9, 10, 11, 12]),
          ])
    func soundsWhileTheShipIsBlowingUp(commands: [String], soundingTurns: [Int]) async throws {
        let saves = FileManager.default.temporaryDirectory.appendingPathComponent("planetfall-alert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: saves) }
        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!, storyURL: GameLocator.storyURL()!,
                                  savesDirectory: saves, randomSeed: 8)
        var sounding = false
        var history: [Bool] = []
        session.addObserver { event in
            guard case .turn(let turn) = event else { return }
            sounding = RedAlert.isSounding(after: turn.text, wasSounding: sounding)
            history.append(sounding)
        }
        try session.start()
        defer { session.stop() }
        for expected in 1...(commands.count + 1) {
            for _ in 0..<100 where history.count < expected { try await Task.sleep(for: .milliseconds(20)) }
            if expected <= commands.count { session.send(commands[expected - 1]) }
        }
        #expect(history.count == commands.count + 1)
        #expect(history.indices.filter { history[$0] } == soundingTurns)
    }
}
