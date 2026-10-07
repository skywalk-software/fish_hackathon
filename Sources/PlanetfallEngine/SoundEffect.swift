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

    public static let explosionDuration = 3.2

    /// A sharp crack, a roaring blast whose tone darkens as it fades, a sub-bass rumble that
    /// sinks in pitch, and debris crackling down for the first second or so.
    static func explosion(sampleRate: Int) -> Data {
        let rate = Double(sampleRate)
        let count = Int(explosionDuration * rate)
        var random = SplitMix64(seed: 0x9E37_79B9_7F4A_7C15)
        var samples = [Double](repeating: 0, count: count)
        var lowPass1 = 0.0, lowPass2 = 0.0
        var rumblePhase = 0.0, rumbleWobble = 0.0
        var crackle = 0.0

        for index in 0..<count {
            let t = Double(index) / rate
            let noise = random.nextSigned()
            let attack = min(1, t / 0.005)

            // Crack: a burst of bright noise over the first few tens of milliseconds.
            let crack = noise * exp(-t / 0.012)
            // Blast: noise through two low-passes whose cutoff falls from 4 kHz to 120 Hz.
            let cutoff = 120 + 3_880 * exp(-t / 0.35)
            let coefficient = 1 - exp(-2 * Double.pi * cutoff / rate)
            lowPass1 += coefficient * (noise - lowPass1)
            lowPass2 += coefficient * (lowPass1 - lowPass2)
            let blast = 3 * lowPass2 * attack * exp(-t / 0.7)
            // Rumble: a sine sinking from 65 Hz to 32 Hz, wobbling slowly in level.
            rumblePhase += 2 * Double.pi * (32 + 33 * exp(-t / 0.6)) / rate
            rumbleWobble = (rumbleWobble + noise * 0.02) * 0.998
            let rumble = sin(rumblePhase) * (0.55 + rumbleWobble) * attack * exp(-t / 0.8)
            // Debris: sparse crackles from 0.15 s to 1.8 s, thinning out as they go.
            if t > 0.15, t < 1.8, random.nextUnit() < 25 / rate * exp(-(t - 0.15) / 0.6) {
                crackle = 0.5 * exp(-(t - 0.15) / 0.8)
            }
            let debris = noise * crackle
            crackle *= pow(0.93, 24_000 / rate)

            samples[index] = crack + blast + rumble + debris
        }

        // Soft-clip for punch, normalize the peak, and ease the tail to silence over the last
        // 1.2 s so it dies away instead of stopping.
        samples = samples.map { tanh(1.5 * $0) }
        let peak = samples.map(abs).max() ?? 1
        let fadeStart = Int((explosionDuration - 1.2) * rate)
        var pcm = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let progress = Double(max(0, index - fadeStart)) / Double(count - 1 - fadeStart)
            let fade = 0.5 * (1 + cos(Double.pi * progress))
            pcm[index] = Int16((samples[index] / peak * peakLevel * fade * Double(Int16.max)).rounded())
        }
        return pcm.map(\.littleEndian).withUnsafeBytes { Data($0) }
    }

    /// Loud, but leaves a little headroom under the voices' level.
    static let peakLevel = 0.85
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
