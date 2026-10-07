import Foundation

/// The Feinstein's red alert: a whooping emergency siren over the hull's rumble and distant
/// blasts. It sounds from the first big explosion until the ship is gone (you got away in the
/// escape pod), you die, or the game restarts, playing quietly on a loop under the voices.
public enum RedAlert {
    static let startTrigger = "A massive explosion rocks the ship"
    static let stopTriggers = [
        "blows the Feinstein into tiny pieces",  // seen from the escape pod
        "You have died",
        StoryEvent.gameStartMarker,              // restarted
    ]

    /// Whether the alert is sounding after a turn's text, given whether it was before.
    public static func isSounding(after text: String, wasSounding: Bool) -> Bool {
        if stopTriggers.contains(where: text.contains) { return false }
        return wasSounding || text.contains(startTrigger)
    }

    public static let loopDuration = 6.0
    /// One whoop of the siren every 1.5 s, so four fit the loop exactly.
    static let sirenPeriod = 1.5
    static let peakLevel = 0.8

    /// The alert as a seamless loop of 16-bit little-endian mono PCM.
    public static func loop(sampleRate: Int) -> Data {
        let rate = Double(sampleRate)
        let count = Int(loopDuration * rate)
        var random = SplitMix64(seed: 0xA1A2_7EDA_1E57_5EED)

        // Siren: a band-limited square-ish tone sweeping up from 420 Hz to 980 Hz over 1.1 s,
        // then 0.4 s of quiet, like a ship's whooping alarm.
        var siren = [Double](repeating: 0, count: count)
        var phase = 0.0
        for index in 0..<count {
            let local = (Double(index) / rate).truncatingRemainder(dividingBy: sirenPeriod)
            if local < 0.5 / rate { phase = 0 }
            let sweep = 1.1
            guard local < sweep else { continue }
            let frequency = 420 * pow(980.0 / 420, pow(local / sweep, 0.8))
            phase += 2 * Double.pi * frequency / rate
            let envelope = min(1, local / 0.02) * min(1, (sweep - local) / 0.04)
            siren[index] = envelope * (sin(phase) + sin(3 * phase) / 3 + sin(5 * phase) / 5)
        }

        // Rumble: noise through two 60 Hz low-passes, swelling every 3 s. Rendered 0.5 s long
        // and crossfaded into its own start so the loop has no seam.
        let crossfade = Int(0.5 * rate)
        var longRumble = [Double](repeating: 0, count: count + crossfade)
        var lowPass1 = 0.0, lowPass2 = 0.0
        let coefficient = 1 - exp(-2 * Double.pi * 60 / rate)
        for index in longRumble.indices {
            lowPass1 += coefficient * (random.nextSigned() - lowPass1)
            lowPass2 += coefficient * (lowPass1 - lowPass2)
            let t = Double(index) / rate
            longRumble[index] = lowPass2 * (0.75 + 0.25 * sin(2 * Double.pi * t / 3))
        }
        var rumble = Array(longRumble[0..<count])
        for index in 0..<crossfade {
            let mix = Double(index) / Double(crossfade)
            // Equal-power: the two noise segments are unrelated.
            rumble[index] = longRumble[index] * mix.squareRoot() + longRumble[count + index] * (1 - mix).squareRoot()
        }

        // Thuds: distant blasts, each a decaying 45 Hz boom with a little noise.
        var thuds = [Double](repeating: 0, count: count)
        for start in [2.3, 4.6] {
            var noiseLowPass = 0.0
            let first = Int(start * rate)
            for index in first..<min(count, first + Int(1.2 * rate)) {
                let local = Double(index - first) / rate
                noiseLowPass += 0.05 * (random.nextSigned() - noiseLowPass)
                let decay = min(1, local / 0.01) * exp(-local / 0.35)
                thuds[index] = decay * (sin(2 * Double.pi * 45 * local) + 4 * noiseLowPass)
            }
        }

        func normalized(_ samples: [Double]) -> [Double] {
            let peak = samples.map(abs).max() ?? 1
            return peak > 0 ? samples.map { $0 / peak } : samples
        }
        let sirenMix = normalized(siren), rumbleMix = normalized(rumble), thudMix = normalized(thuds)
        let mixed = (0..<count).map { 0.45 * sirenMix[$0] + 0.6 * rumbleMix[$0] + 0.5 * thudMix[$0] }
        let pcm = normalized(mixed).map { Int16(($0 * peakLevel * Double(Int16.max)).rounded()) }
        return pcm.map(\.littleEndian).withUnsafeBytes { Data($0) }
    }
}
