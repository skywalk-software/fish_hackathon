import Foundation

/// Sound effects for story moments, played before anyone speaks. They're synthesized rather than
/// recorded, so there's no audio file (or license) to ship, and they sound the same every time.
public enum SoundEffect: String, CaseIterable, Sendable {
    /// The Feinstein starts blowing up (`StoryEvent` "explosion").
    case explosion

    /// The effects a turn's text calls for: one per `StoryEvent` it triggers that has a sound.
    public static func triggered(by text: String) -> [SoundEffect] {
        StoryEvent.triggered(by: text).compactMap { SoundEffect(rawValue: $0.id) }
    }

    /// The effect as 16-bit little-endian mono PCM.
    public func pcm(sampleRate: Int) -> Data {
        switch self {
        case .explosion: Self.explosion(sampleRate: sampleRate)
        }
    }

    public static let explosionDuration = 6.5

    /// One blast: a crack, then roaring noise whose tone darkens as it fades.
    private struct Boom {
        let start: Double
        let size: Double
        /// How fast the roar dies away, in seconds.
        let decay: Double
        var lowPass1 = 0.0
        var lowPass2 = 0.0
    }

    /// A main blast and two aftershocks as the hull gives way, over a deep rumble that sinks in
    /// pitch and holds for several seconds, with debris crackling down for the first four.
    static func explosion(sampleRate: Int) -> Data {
        let rate = Double(sampleRate)
        let count = Int(explosionDuration * rate)
        var random = SplitMix64(seed: 0x9E37_79B9_7F4A_7C15)
        var samples = [Double](repeating: 0, count: count)
        var booms = [
            Boom(start: 0, size: 1, decay: 1.4),
            Boom(start: 0.85, size: 0.6, decay: 0.9),
            Boom(start: 2.1, size: 0.45, decay: 0.8),
        ]
        var rumblePhase = 0.0, rumbleWobble = 0.0, deepNoise = 0.0
        var crackle = 0.0
        let deepNoiseCoefficient = 1 - exp(-2 * Double.pi * 90 / rate)

        for index in 0..<count {
            let t = Double(index) / rate
            let noise = random.nextSigned()

            var blasts = 0.0
            for b in booms.indices where t >= booms[b].start {
                let local = t - booms[b].start
                let attack = min(1, local / 0.004)
                // Crack: a burst of bright noise over the first few tens of milliseconds.
                let crack = noise * exp(-local / 0.015)
                // Roar: noise through two low-passes whose cutoff falls from 5 kHz to 80 Hz.
                let cutoff = 80 + 4_920 * exp(-local / 0.45)
                let coefficient = 1 - exp(-2 * Double.pi * cutoff / rate)
                booms[b].lowPass1 += coefficient * (noise - booms[b].lowPass1)
                booms[b].lowPass2 += coefficient * (booms[b].lowPass1 - booms[b].lowPass2)
                let roar = 3.2 * booms[b].lowPass2 * attack * exp(-local / booms[b].decay)
                blasts += booms[b].size * (crack + roar)
            }

            // Rumble: two detuned sines sinking from 55 Hz to 25 Hz plus very deep noise,
            // wobbling slowly in level.
            let frequency = 25 + 30 * exp(-t / 1.0)
            rumblePhase += 2 * Double.pi * frequency / rate
            rumbleWobble = (rumbleWobble + noise * 0.02) * 0.998
            deepNoise += deepNoiseCoefficient * (noise - deepNoise)
            let tone = 0.45 * sin(rumblePhase) + 0.3 * sin(rumblePhase * 1.07)
            let rumble = (tone + 6 * deepNoise) * (0.7 + rumbleWobble) * min(1, t / 0.01) * exp(-t / 2.2)

            // Debris: crackles from 0.2 s to 4.5 s, thinning out as they go.
            if t > 0.2, t < 4.5, random.nextUnit() < 35 / rate * exp(-(t - 0.2) / 1.2) {
                crackle = 0.55 * exp(-(t - 0.2) / 1.5)
            }
            let debris = noise * crackle
            crackle *= pow(0.93, 24_000 / rate)

            samples[index] = blasts + rumble + debris
        }

        // Soft-clip for punch, normalize the peak, and ease the tail to silence over the last
        // 2 s so it dies away instead of stopping.
        samples = samples.map { tanh(1.8 * $0) }
        let peak = samples.map(abs).max() ?? 1
        let fadeStart = Int((explosionDuration - 2) * rate)
        var pcm = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let progress = Double(max(0, index - fadeStart)) / Double(count - 1 - fadeStart)
            let fade = 0.5 * (1 + cos(Double.pi * progress))
            pcm[index] = Int16((samples[index] / peak * peakLevel * fade * Double(Int16.max)).rounded())
        }
        return pcm.map(\.littleEndian).withUnsafeBytes { Data($0) }
    }

    /// Big, with a little headroom left so it never clips.
    static let peakLevel = 0.92
}

/// A small, fast, seeded random number generator, so the effect is identical every time.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// Uniform in [-1, 1).
    mutating func nextSigned() -> Double {
        nextUnit() * 2 - 1
    }
}
