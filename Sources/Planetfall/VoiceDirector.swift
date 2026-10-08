import Foundation
import PlanetfallEngine

/// Gives the game its voices, all through Fish Audio TTS and one shared speaker so nobody talks
/// over anybody. After each action:
/// 0. story sound effects play first (the explosion that starts the Feinstein blowing up),
///    and from then on the red alert (siren and rumble) loops quietly underneath until the ship
///    is gone, the player dies, or the game restarts,
/// 1. the narrator reads Claude's retelling of the scene (character lines left out),
/// 2. each character speaks their own lines (Blather as "arnold", Floyd, Veldina),
/// 3. SNARK-9 delivers its commentary when its quip arrives.
/// Sending a command, or starting push-to-talk, cuts everyone off.
@MainActor
@Observable
final class VoiceDirector {
    /// The last failure (bad key, voice not available to this account), until the next line plays.
    private(set) var errorMessage: String?
    /// Each part on or off. Remembered between launches.
    var narratorEnabled: Bool { didSet { settingChanged(narratorEnabled, key: Self.narratorKey) } }
    var charactersEnabled: Bool { didSet { settingChanged(charactersEnabled, key: Self.charactersKey) } }
    var sidekickEnabled: Bool { didSet { settingChanged(sidekickEnabled, key: Self.sidekickKey) } }
    var effectsEnabled: Bool {
        didSet {
            settingChanged(effectsEnabled, key: Self.effectsKey)
            updateAlert()
        }
    }
    /// The narrator needs an Anthropic key; SNARK-9's voice needs SNARK-9.
    let hasNarrator: Bool
    let hasSidekick: Bool

    private struct Utterance {
        enum Role { case effect, narrator, character, sidekick }
        let role: Role
        let speaker: String
        let voiceID: String
        /// Text to speak, a piece at a time (the narrator streams sentences from Claude).
        let texts: AsyncThrowingStream<String, Error>
        /// Stops producing `texts`, e.g. cancels the narrator's Claude request.
        var cancel: () -> Void = {}
        /// Audio to play as is (sound effects), instead of speaking `texts`.
        var sound: Data?

        static func effect(_ effect: SoundEffect) -> Utterance {
            Utterance(role: .effect, speaker: effect.rawValue, voiceID: "",
                      texts: AsyncThrowingStream { $0.finish() },
                      sound: effect.pcm(sampleRate: FishTextToSpeech.sampleRate))
        }

        static func single(_ role: Role, speaker: String, voiceID: String, text: String) -> Utterance {
            Utterance(role: role, speaker: speaker, voiceID: voiceID, texts: AsyncThrowingStream { continuation in
                continuation.yield(text)
                continuation.finish()
            })
        }
    }

    @ObservationIgnored private weak var session: GameSession?
    @ObservationIgnored private let speech: FishTextToSpeech
    @ObservationIgnored private let cast: VoiceCast
    @ObservationIgnored private let narrator: Narrator?
    @ObservationIgnored private let cache: VoiceLineCache
    @ObservationIgnored private let player = PCMStreamPlayer(sampleRate: FishTextToSpeech.sampleRate)
    @ObservationIgnored private var queue: [Utterance] = []
    @ObservationIgnored private var current: Utterance?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastCommand: String?
    /// The red alert's loop, separate from the speech queue so commands don't silence it.
    @ObservationIgnored private let alertPlayer = LoopPlayer(sampleRate: FishTextToSpeech.sampleRate)
    @ObservationIgnored private var alertSounding = false
    @ObservationIgnored private var isListening = false
    @ObservationIgnored private var alertFade: Task<Void, Never>?
    @ObservationIgnored private var previousNarration: [String] = []

    private static let narratorKey = "narratorVoiceEnabled"
    private static let charactersKey = "characterVoicesEnabled"
    private static let sidekickKey = "sidekickVoiceEnabled"
    private static let effectsKey = "soundEffectsEnabled"
    private static let maxPreviousNarration = 3
    /// Under the voices, so they stay clear.
    private static let alertVolume: Float = 0.35

    /// Nil without a Fish API key. The narrator also needs an Anthropic key.
    static func makeDefault(session: GameSession, sidekick: Sidekick?) -> VoiceDirector? {
        FishAPIKey.load().map {
            VoiceDirector(session: session, speech: FishTextToSpeech(apiKey: $0), cast: VoiceCast.load(),
                          narrator: AnthropicAPIKey.load().map { Narrator(apiKey: $0) }, sidekick: sidekick)
        }
    }

    init(session: GameSession, speech: FishTextToSpeech, cast: VoiceCast, narrator: Narrator?,
         sidekick: Sidekick?, cache: VoiceLineCache = .default) {
        self.session = session
        self.speech = speech
        self.cast = cast
        self.narrator = narrator
        self.cache = cache
        hasNarrator = narrator != nil
        hasSidekick = sidekick != nil
        let defaults = UserDefaults.standard
        narratorEnabled = defaults.object(forKey: Self.narratorKey) as? Bool ?? true
        charactersEnabled = defaults.object(forKey: Self.charactersKey) as? Bool ?? true
        sidekickEnabled = defaults.object(forKey: Self.sidekickKey) as? Bool ?? true
        effectsEnabled = defaults.object(forKey: Self.effectsKey) as? Bool ?? true

        session.addObserver { [weak self] event in
            guard let self else { return }
            switch event {
            case .turn(let turn):
                self.turnArrived(turn)
            case .command(let command):
                self.lastCommand = command
                self.stop()
            case .ended:
                self.stop()
                self.alertSounding = false
                self.updateAlert()
            case .achievementUnlocked:
                break  // SNARK-9 announces it; its line is voiced like any other.
            }
        }
        sidekick?.onLineFinished { [weak self] line in self?.sidekickSaid(line) }
    }

    /// Cuts off whoever is speaking and drops everything queued.
    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        current?.cancel()
        current = nil
        queue.forEach { $0.cancel() }
        queue.removeAll()
        player.stop()
    }

    /// Forget the previous game's narration (e.g. after a restart).
    func reset() {
        stop()
        lastCommand = nil
        previousNarration = []
        alertSounding = false
        alertFade?.cancel()
        alertPlayer.stop()
    }

    /// Push-to-talk is recording: duck the red alert so the microphone doesn't hear it.
    func setListening(_ listening: Bool) {
        isListening = listening
        updateAlert()
    }

    /// Starts, fades, ducks, or stops the red alert to match the game and settings.
    private func updateAlert(startDelay: Double = 0) {
        let audible = alertSounding && effectsEnabled
        let target: Float = audible && !isListening ? Self.alertVolume : 0
        if audible, !alertPlayer.isPlaying {
            alertPlayer.volume = 0
            alertPlayer.play(RedAlert.loop(sampleRate: FishTextToSpeech.sampleRate))
        }
        guard alertPlayer.isPlaying else { return }
        // Fade in slowly as it starts, duck quickly for the microphone, fade out when it's over.
        let duration = !audible ? 1.5 : target == 0 ? 0.15 : startDelay > 0 ? 2.0 : 0.4
        fadeAlert(to: target, over: duration, after: startDelay, thenStop: !audible)
    }

    private func fadeAlert(to target: Float, over duration: Double, after delay: Double, thenStop: Bool) {
        alertFade?.cancel()
        alertFade = Task { [alertPlayer] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            let start = alertPlayer.volume
            let steps = max(1, Int(duration / 0.05))
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                alertPlayer.volume = start + (target - start) * Float(step) / Float(steps)
                try? await Task.sleep(for: .milliseconds(50))
            }
            if thenStop, !Task.isCancelled { alertPlayer.stop() }
        }
    }

    private func settingChanged(_ isOn: Bool, key: String) {
        UserDefaults.standard.set(isOn, forKey: key)
        if !isOn { stop() }
    }

    // MARK: - Casting each turn

    private func turnArrived(_ turn: GameTurn) {
        let sounding = RedAlert.isSounding(after: turn.text, wasSounding: alertSounding)
        if sounding != alertSounding {
            alertSounding = sounding
            // Let the explosion hit first, then bring the siren up under it.
            updateAlert(startDelay: sounding ? 1.0 : 0)
        }
        // Effects go to the front of the queue, so they play before anything else this turn.
        if effectsEnabled {
            for effect in SoundEffect.triggered(by: turn.text).reversed() { enqueue(.effect(effect), first: true) }
        }
        let script = DialogueExtractor.script(for: turn.text, voices: cast.characters)
        if narratorEnabled, let narrator,
           !script.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let context = NarrationContext(location: turn.status?.location ?? session?.status?.location,
                                           command: lastCommand, output: script.narration,
                                           previousNarration: previousNarration)
            // Start Claude now, while anything already queued is still playing.
            let (texts, continuation) = AsyncThrowingStream<String, Error>.makeStream()
            let producer = Task {
                do {
                    for try await sentence in narrator.sentences(for: context) { continuation.yield(sentence) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            enqueue(Utterance(role: .narrator, speaker: "Narrator", voiceID: cast.narratorVoiceID,
                              texts: texts, cancel: { producer.cancel() }))
        }
        guard charactersEnabled else { return }
        for line in script.lines {
            guard let voice = cast.characters.first(where: { $0.characterID == line.characterID }) else { continue }
            enqueue(.single(.character, speaker: voice.names[0], voiceID: voice.fishVoiceID, text: line.ttsText))
        }
    }

    private func sidekickSaid(_ line: String) {
        guard sidekickEnabled else { return }
        enqueue(.single(.sidekick, speaker: "SNARK-9", voiceID: cast.sidekickVoiceID, text: line))
    }

    // MARK: - Playback

    private func enqueue(_ utterance: Utterance, first: Bool = false) {
        if first { queue.insert(utterance, at: 0) } else { queue.append(utterance) }
        guard task == nil else { return }
        let generation = self.generation
        task = Task { await playQueue(generation: generation) }
    }

    /// Speaks queued utterances in order. Audio is scheduled on one player, so each starts as
    /// soon as the previous one ends.
    private func playQueue(generation: Int) async {
        while !queue.isEmpty, !Task.isCancelled {
            let utterance = queue.removeFirst()
            current = utterance
            if let sound = utterance.sound {
                player.enqueue(sound)
                continue
            }
            var spoken: [String] = []
            do {
                for try await text in utterance.texts {
                    try await speak(text, voiceID: utterance.voiceID, cacheable: utterance.role == .character)
                    spoken.append(text)
                }
                if utterance.role == .narrator, !spoken.isEmpty {
                    previousNarration.append(spoken.joined(separator: " "))
                    previousNarration = previousNarration.suffix(Self.maxPreviousNarration)
                }
                errorMessage = nil
            } catch is CancellationError {
                break
            } catch CommandInterpreterError.refused {
                continue  // Claude declined to narrate this turn; just move on.
            } catch {
                guard !Task.isCancelled else { break }
                errorMessage = "\(utterance.speaker) couldn't speak: \(error.localizedDescription)"
            }
        }
        // A stop() during playback already reset state, and may have started a newer queue.
        guard generation == self.generation else { return }
        current = nil
        task = nil
    }

    /// Streams one piece of text in `voiceID` into the player. Character lines repeat, so
    /// finished ones are cached; narration and commentary are new every time.
    private func speak(_ text: String, voiceID: String, cacheable: Bool) async throws {
        if cacheable, let cached = cache.load(text: text, voiceID: voiceID, model: speech.model) {
            try Task.checkCancellation()
            player.enqueue(cached)
            return
        }
        var audio = Data()
        for try await chunk in speech.stream(text, voiceID: voiceID) {
            // After stop(), a chunk already in flight must not restart the player.
            try Task.checkCancellation()
            player.enqueue(chunk)
            if cacheable { audio.append(chunk) }
        }
        // A cancelled stream just ends early; only cache lines that arrived whole.
        try Task.checkCancellation()
        if cacheable { cache.store(audio, text: text, voiceID: voiceID, model: speech.model) }
    }
}
