import Foundation
import Testing
@testable import PlanetfallEngine

struct SoundEffectTests {
    private let sampleRate = 24_000

    private func samples(_ effect: SoundEffect) -> [Int16] {
        effect.pcm(sampleRate: sampleRate).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }.map(Int16.init(littleEndian:))
    }

    private func rms(_ samples: ArraySlice<Int16>) -> Double {
        (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
    }

    @Test func theFirstBigExplosionTriggersIt() {
        #expect(SoundEffect.triggered(by: "Time passes...\n\nA massive explosion rocks the ship. Echoes from the explosion resound deafeningly down the halls. The door to port slides open.") == [.explosion])
        #expect(SoundEffect.triggered(by: "Time passes...").isEmpty)
        #expect(SoundEffect.triggered(by: "Explosions continue to rock the ship.").isEmpty)
    }

    @Test func explosionHitsAtOnceAndDiesAway() {
        let pcm = samples(.explosion)
        #expect(pcm.count == Int(SoundEffect.explosionDuration * Double(sampleRate)))

        // Peak normalized just under the voices' level.
        let peak = pcm.map { abs(Int($0)) }.max() ?? 0
        #expect(abs(Double(peak) / Double(Int16.max) - SoundEffect.peakLevel) < 0.01)

        // Loud from the first few milliseconds: no lead-in before the bang.
        let firstFiveMilliseconds = pcm.prefix(sampleRate / 200)
        #expect(firstFiveMilliseconds.map { abs(Int($0)) }.max()! > Int(Int16.max) / 4)

        // Most of the energy is up front, and it fades out to silence.
        let quarterSecond = sampleRate / 4
        let start = rms(pcm[0..<quarterSecond])
        let end = rms(pcm[(pcm.count - quarterSecond)...])
        #expect(start > 20 * end)
        #expect(pcm.last == 0)
    }

    @Test func soundsTheSameEveryTime() {
        #expect(SoundEffect.explosion.pcm(sampleRate: sampleRate) == SoundEffect.explosion.pcm(sampleRate: sampleRate))
    }

    /// The real game: with seed 8 the Feinstein starts exploding on the ninth wait.
    @MainActor
    @Test(.enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
    func playsWhenTheFeinsteinStartsBlowingUp() async throws {
        let saves = FileManager.default.temporaryDirectory.appendingPathComponent("planetfall-sfx-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: saves) }
        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!, storyURL: GameLocator.storyURL()!,
                                  savesDirectory: saves, randomSeed: 8)
        var effectsByTurn: [[SoundEffect]] = []
        session.addObserver { event in
            if case .turn(let turn) = event { effectsByTurn.append(SoundEffect.triggered(by: turn.text)) }
        }
        try session.start()
        defer { session.stop() }
        for expected in 1...11 {
            for _ in 0..<100 where effectsByTurn.count < expected { try await Task.sleep(for: .milliseconds(20)) }
            if expected < 11 { session.send("wait") }
        }
        // Turn 1 is the opening; turn 10 is the result of the ninth wait. Later explosions don't repeat it.
        #expect(effectsByTurn.count == 11)
        #expect(effectsByTurn.indices.filter { !effectsByTurn[$0].isEmpty } == [9])
        #expect(effectsByTurn[9] == [.explosion])
    }
}
