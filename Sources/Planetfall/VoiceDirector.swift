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
    /// The character whose voice is playing right now (for their portrait's jaw), if any.
    private(set) var speakingCharacterID: String?
    /// How far that character's jaw is open, 0 to 1, following the loudness of their speech.
    private(set) var mouthOpenness: Double = 0
    /// Why the narrator last fell back from Claude's retelling to the game text, if it has.
    private(set) var narrationFallbackReason: String?
    /// The last failure (bad key, voice not available to this account), until the next line plays.
    private(set) var errorMessage: String?
    /// Each part on or off. Remembered between launches.
    var narratorEnabled: Bool { didSet { settingChanged(narratorEnabled, key: Self.narratorKey) } }
    var charactersEnabled: Bool { didSet { settingChanged(charactersEnabled, key: Self.charactersKey) } }
    var sidekickEnabled: Bool {
        didSet {
            settingChanged(sidekickEnabled, key: Self.sidekickKey)
            // With SNARK-9's voice off, its caption shouldn't wait for speech that never comes.
            sidekick?.captionWaitsForVoice = sidekickEnabled
        }
    }
    var effectsEnabled: Bool {
        didSet {
            settingChanged(effectsEnabled, key: Self.effectsKey)
            updateAlert()
        }
    }
    /// Whether character portraits move their jaws (and SNARK-9's lens glows) as they speak.
    var talkingPortraitsEnabled: Bool {
        didSet { UserDefaults.standard.set(talkingPortraitsEnabled, forKey: Self.portraitsKey) }
    }
    /// What the narrator reads: Claude's retelling of the turn, or the game's own text.
    enum NarratorMode: String, CaseIterable, Identifiable {
        case claude, gameText
        var id: String { rawValue }
        var title: String {
            switch self {
            case .claude: "Claude's Retelling"
            case .gameText: "Read the Game Text"
            }
        }
    }
    /// The Narrator menu's choice: Claude's embellished retelling, the original game text, or no
    /// narrator. Combines `narratorEnabled` and `narratorMode`.
    enum NarratorChoice: String, CaseIterable, Identifiable {
        case embellished, original, none
        var id: String { rawValue }
        var title: String {
            switch self {
            case .embellished: "Embellished Text"
            case .original: "Original Text"
            case .none: "None"
            }
        }
    }
    var narratorChoice: NarratorChoice {
        get { !narratorEnabled ? .none : narratorMode == .claude ? .embellished : .original }
        set {
            narratorEnabled = newValue != .none
            if newValue != .none { narratorMode = newValue == .embellished ? .claude : .gameText }
        }
    }
    /// Remembered between launches. Claude's retelling falls back to the game text whenever
    /// Claude can't be reached (no key, a rejected key, no credit).
    var narratorMode: NarratorMode {
        didSet { UserDefaults.standard.set(narratorMode.rawValue, forKey: Self.narratorModeKey) }
    }
    /// The narrator's retelling needs an Anthropic key (reading the game text doesn't);
    /// SNARK-9's voice needs SNARK-9.
    let hasNarrator: Bool
    let hasSidekick: Bool

    private struct Utterance {
        enum Role { case effect, narrator, character, sidekick }
        let role: Role
        /// Tags this utterance's audio in the player, so space can skip just this speaker.
        var id = 0
        /// The game character speaking (for their portrait's moving jaw), if it's a character.
        var characterID: String?
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

        static func single(_ role: Role, speaker: String, voiceID: String, text: String,
                           characterID: String? = nil) -> Utterance {
            var utterance = Utterance(role: role, speaker: speaker, voiceID: voiceID,
                                      texts: AsyncThrowingStream { continuation in
                                          continuation.yield(text)
                                          continuation.finish()
                                      })
            utterance.characterID = characterID
            return utterance
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
    /// Whether `current` has produced all its text (e.g. the narrator's Claude stream ended).
    @ObservationIgnored private var currentProduced = false
    @ObservationIgnored private weak var sidekick: Sidekick?
    @ObservationIgnored private var nextUtteranceID = 1
    /// Who each queued or playing utterance is, by id (for skipping).
    @ObservationIgnored private var roles: [Int: Utterance.Role] = [:]
    /// Which game character each character line's audio belongs to, by id.
    @ObservationIgnored private var segmentCharacters: [Int: String] = [:]
    /// An utterance the player skipped while it was still producing audio.
    @ObservationIgnored private var skippedID: Int?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastCommand: String?
    /// The red alert's loop, separate from the speech queue so commands don't silence it.
    @ObservationIgnored private let alertPlayer = LoopPlayer(sampleRate: FishTextToSpeech.sampleRate)
    @ObservationIgnored private var alertSounding = false
    /// The session's plugged-ears state when the siren was last updated.
    @ObservationIgnored private var earsWerePlugged = false
    @ObservationIgnored private var isListening = false
    @ObservationIgnored private var alertFade: Task<Void, Never>?
    @ObservationIgnored private var previousNarration: [String] = []

    private static let narratorKey = "narratorVoiceEnabled"
    private static let charactersKey = "characterVoicesEnabled"
    private static let sidekickKey = "sidekickVoiceEnabled"
    private static let effectsKey = "soundEffectsEnabled"
    private static let portraitsKey = "talkingPortraitsEnabled"
    private static let narratorModeKey = "narratorMode"
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
        narratorMode = defaults.string(forKey: Self.narratorModeKey).flatMap(NarratorMode.init) ?? .claude
        talkingPortraitsEnabled = defaults.object(forKey: Self.portraitsKey) as? Bool ?? true

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
        self.sidekick = sidekick
        sidekick?.onLineFinished { [weak self] line in self?.sidekickSaid(line) }
        sidekick?.captionWaitsForVoice = sidekickEnabled
        // SNARK-9 asks Claude for its quip only as the narration is wrapping up, so a burst
        // of quick commands doesn't pay for quips nobody would hear.
        sidekick?.readyToComment = { [weak self] in await self?.waitUntilNarrationNearlyDone() }
        Task { [weak self] in await self?.animateMouths() }
    }

    /// About 30 times a second, sets the speaking character's jaw from how loud their audio is
    /// at that moment: it opens quickly and closes a little slower, so it doesn't jitter.
    private func animateMouths() async {
        while !Task.isCancelled {
            var target = 0.0
            var speaker: String?
            if talkingPortraitsEnabled, let now = player.currentLevel,
               let characterID = segmentCharacters[now.segment]
                   ?? (roles[now.segment] == .sidekick ? sidekick?.persona.artID : nil) {
                speaker = characterID
                // Speech RMS runs roughly 0.02 (quiet) to 0.2 (loud).
                target = min(1, max(0, (Double(now.level) - 0.02) / 0.14))
            }
            let rate = target > mouthOpenness ? 0.6 : 0.3
            var next = mouthOpenness + (target - mouthOpenness) * rate
            // Snap shut once nearly closed and quiet, rather than creeping toward zero and
            // leaving a hairline gap.
            if target < 0.05, next < 0.05 { next = 0 }
            let settled = next == 0 && speaker == nil
            // Only touch observed state when it changes visibly, to keep SwiftUI work low.
            if abs(next - mouthOpenness) > 0.01 || (next == 0 && mouthOpenness != 0) {
                mouthOpenness = next
            }
            if let speaker, speaker != speakingCharacterID { speakingCharacterID = speaker }
            if settled, speakingCharacterID != nil { speakingCharacterID = nil }
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    /// Returns once no narration is queued and the current one has finished being written,
    /// with at most `lead` seconds of audio left to play. Gives up after 30 s.
    func waitUntilNarrationNearlyDone(lead: Double = 2.5) async {
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline {
            let narrationPending = queue.contains { $0.role == .narrator }
                || (current?.role == .narrator && !currentProduced)
            if !narrationPending, player.secondsRemaining <= lead { return }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
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
        roles = [:]
        segmentCharacters = [:]
        skippedID = nil
        player.stop()
    }

    /// Cuts off whoever is speaking (the narrator, a character, SNARK-9, or a sound effect) and
    /// lets the next one start: skip the narrator and SNARK-9 speaks next. Returns false when
    /// nobody is speaking. Press space on an empty command line to call this.
    @discardableResult
    func skipSpeaker() -> Bool {
        // The audible speaker, or, before any audio arrives, the one being prepared.
        let audible = player.audibleSegment
        guard let id = audible ?? (currentProduced ? nil : current?.id) else { return false }
        player.skip(segment: id)
        if current?.id == id, !currentProduced {
            // Still producing: stop its text (e.g. the narrator's Claude stream) and audio.
            skippedID = id
            current?.cancel()
        }
        // Skipping SNARK-9 only stops his voice; his caption stays (or appears, if he was
        // skipped before his audio started).
        if roles[id] == .sidekick { sidekick?.revealCaption() }
        return true
    }

    /// Reveals SNARK-9's caption once its audio (`id`) is the one playing.
    private func revealCaptionWhenAudible(_ id: Int, generation: Int) {
        Task { [weak self] in
            let deadline = ContinuousClock.now + .seconds(60)
            while ContinuousClock.now < deadline {
                guard let self, self.generation == generation else { return }
                if self.skippedID == id {
                    self.sidekick?.revealCaption()
                    return
                }
                if let audible = self.player.audibleSegment, audible >= id {
                    if audible == id { self.sidekick?.revealCaption() }
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
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
        // Plugged ears (an app command) silence only the siren; everything else keeps playing.
        let audible = alertSounding && effectsEnabled && !(session?.earsPlugged ?? false)
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
        if turn.isCheat {
            // A cheat jumped ahead in a fresh game: start the narration history over.
            previousNarration = []
        }
        // After a cheat, the siren follows the story state (on while the ship is exploding);
        // otherwise it follows the turn's text.
        let sounding = turn.isCheat
            ? session?.storyEvents.contains("explosion") ?? false
            : RedAlert.isSounding(after: turn.text, wasSounding: alertSounding)
        if sounding != alertSounding {
            alertSounding = sounding
            // Let the explosion hit first, then bring the siren up under it.
            updateAlert(startDelay: sounding ? 1.0 : 0)
        }
        let earsPlugged = session?.earsPlugged ?? false
        if earsPlugged != earsWerePlugged {
            earsWerePlugged = earsPlugged
            updateAlert()
        }
        // Effects go to the front of the queue, so they play before anything else this turn.
        if effectsEnabled {
            for effect in SoundEffect.triggered(by: turn.text).reversed() { enqueue(.effect(effect), first: true) }
        }
        let script = DialogueExtractor.script(for: turn.text, voices: cast.characters)
        let gameText = GameTextNarration.spokenParagraphs(from: script.narration)
        if narratorEnabled, !gameText.isEmpty {
            let context = NarrationContext(location: turn.status?.location ?? session?.status?.location,
                                           command: lastCommand, output: script.narration,
                                           previousNarration: previousNarration)
            let claude = narratorMode == .claude ? narrator : nil
            // Start Claude now, while anything already queued is still playing.
            let (texts, continuation) = AsyncThrowingStream<String, Error>.makeStream()
            let producer = Task { @MainActor [weak self] in
                guard let claude else {
                    for paragraph in gameText { continuation.yield(paragraph) }
                    continuation.finish()
                    return
                }
                var spokeAny = false
                do {
                    for try await sentence in claude.sentences(for: context) {
                        spokeAny = true
                        continuation.yield(sentence)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    guard !Task.isCancelled else {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    // Claude couldn't narrate (bad key, no credit, network): read the game text
                    // instead of going quiet, unless Claude had already started speaking.
                    if !spokeAny {
                        self?.narrationFallbackReason = error.localizedDescription
                        for paragraph in gameText { continuation.yield(paragraph) }
                    }
                    continuation.finish()
                }
            }
            enqueue(Utterance(role: .narrator, speaker: "Narrator", voiceID: cast.narratorVoiceID,
                              texts: texts, cancel: { producer.cancel() }))
        }
        guard charactersEnabled else { return }
        for line in script.lines {
            guard let voice = cast.characters.first(where: { $0.characterID == line.characterID }) else { continue }
            enqueue(.single(.character, speaker: voice.names[0], voiceID: voice.fishVoiceID, text: line.ttsText,
                            characterID: voice.characterID))
        }
    }

    private func sidekickSaid(_ line: String) {
        guard sidekickEnabled else { return }
        enqueue(.single(.sidekick, speaker: "SNARK-9", voiceID: cast.sidekickVoiceID, text: line))
    }

    // MARK: - Playback

    private func enqueue(_ utterance: Utterance, first: Bool = false) {
        var utterance = utterance
        utterance.id = nextUtteranceID
        nextUtteranceID += 1
        roles[utterance.id] = utterance.role
        if let characterID = utterance.characterID { segmentCharacters[utterance.id] = characterID }
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
            currentProduced = false
            if let sound = utterance.sound {
                player.enqueue(sound, segment: utterance.id)
                continue
            }
            var spoken: [String] = []
            // SNARK-9's caption appears when its audio actually starts playing, after whatever
            // is still queued ahead of it (the end of the narration, unless that's skipped).
            if utterance.role == .sidekick { revealCaptionWhenAudible(utterance.id, generation: generation) }
            do {
                for try await text in utterance.texts {
                    guard skippedID != utterance.id else { break }
                    try await speak(text, voiceID: utterance.voiceID, cacheable: utterance.role == .character,
                                    speed: utterance.role == .narrator ? cast.narratorSpeed : 1,
                                    segment: utterance.id)
                    spoken.append(text)
                }
                currentProduced = true
                if utterance.role == .narrator, !spoken.isEmpty {
                    previousNarration.append(DeliveryTags.strip(spoken.joined(separator: " ")))
                    previousNarration = previousNarration.suffix(Self.maxPreviousNarration)
                }
                errorMessage = nil
            } catch is CancellationError {
                // Skipping cancels this speaker's text (e.g. the narrator's Claude request);
                // the queue carries on with the next one.
                if skippedID == utterance.id, !Task.isCancelled { continue }
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
    private func speak(_ text: String, voiceID: String, cacheable: Bool, speed: Double = 1,
                       segment: Int) async throws {
        if cacheable, let cached = cache.load(text: text, voiceID: voiceID, model: speech.model) {
            try Task.checkCancellation()
            player.enqueue(cached, segment: segment)
            return
        }
        var audio = Data()
        for try await chunk in speech.stream(text, voiceID: voiceID, speed: speed) {
            // After stop(), a chunk already in flight must not restart the player.
            try Task.checkCancellation()
            // Skipped mid-line: stop adding this speaker's audio (and don't cache a partial line).
            if skippedID == segment { return }
            player.enqueue(chunk, segment: segment)
            if cacheable { audio.append(chunk) }
        }
        // A cancelled stream just ends early; only cache lines that arrived whole.
        try Task.checkCancellation()
        if cacheable { cache.store(audio, text: text, voiceID: voiceID, model: speech.model) }
    }
}
