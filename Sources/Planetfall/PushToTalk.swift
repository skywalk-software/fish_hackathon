import AppKit
import AVFoundation
import PlanetfallEngine

/// Hold-to-talk voice commands. While ⌥ (or the mic button) is held, the microphone records;
/// on release the clip goes to Fish Audio speech-to-text, Claude turns the transcript into a
/// parser command (when an Anthropic key is set), and the command is handed back only if every
/// word is in the game's vocabulary. Nothing the game can't accept is ever sent.
@MainActor
@Observable
final class PushToTalk {
    enum Phase: Equatable {
        case idle, listening, transcribing, interpreting
    }

    private(set) var phase: Phase = .idle
    /// A hint or error to show the player. Cleared when the next recording starts.
    private(set) var notice: String?
    /// Why voice input is off (no API key), or nil when it's ready.
    let unavailableReason: String?

    @ObservationIgnored private let speechToText: FishSpeechToText?
    /// Nil without ANTHROPIC_API_KEY; transcripts must then pass the vocabulary check as heard.
    @ObservationIgnored private let interpreter: CommandInterpreter?
    /// The parser's dictionary, read from the story file.
    @ObservationIgnored private let vocabulary = GameVocabulary.planetfall
    @ObservationIgnored private let recorder = MicrophoneRecorder()
    @ObservationIgnored private var canListen: () -> Bool = { false }
    @ObservationIgnored private var context: () -> CommandContext = { CommandContext(location: nil, recentOutput: "") }
    @ObservationIgnored private var onCommand: (String) -> Void = { _ in }
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var optionKeyHeld = false

    /// Shorter holds are treated as accidental taps.
    private static let minimumDuration = 0.3
    /// Clips that never get louder than this (about -50 dBFS) are silence; don't pay to transcribe them.
    private static let silencePeak: Int16 = 100

    init() {
        if let key = FishAPIKey.load() {
            speechToText = FishSpeechToText(apiKey: key)
            unavailableReason = nil
        } else {
            speechToText = nil
            unavailableReason = "Voice input is off. Add FISH_API_KEY to \(FishAPIKey.envFileURL.path)."
        }
        interpreter = AnthropicAPIKey.load().map {
            CommandInterpreter(apiKey: $0, vocabulary: GameVocabulary.planetfall?.words)
        }
    }

    /// Starts listening for ⌥ and routes commands to `onCommand`. `context` describes the game
    /// at the moment the player finishes speaking.
    func activate(canListen: @escaping () -> Bool, context: @escaping () -> CommandContext,
                  onCommand: @escaping (String) -> Void) {
        self.canListen = canListen
        self.context = context
        self.onCommand = onCommand
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) }
            return event
        }
    }

    func deactivate() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        cancel()
    }

    func begin() {
        guard phase == .idle, speechToText != nil, canListen() else { return }
        notice = nil
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                notice = granted ? "Microphone ready. Hold ⌥ and speak." : Self.micDeniedMessage
            }
            return
        default:
            notice = Self.micDeniedMessage
            return
        }
        do {
            try recorder.start()
            phase = .listening
        } catch {
            notice = error.localizedDescription
        }
    }

    func end() {
        guard phase == .listening, let speechToText else { return }
        let recording = recorder.stop()
        guard recording.duration >= Self.minimumDuration else {
            phase = .idle
            notice = "Keep holding ⌥ while you speak."
            return
        }
        guard recording.peak > Self.silencePeak else {
            phase = .idle
            notice = "Didn't hear anything. Check your microphone."
            return
        }
        phase = .transcribing
        let wav = WAV.encode(samples: recording.samples, sampleRate: recording.sampleRate)
        let context = self.context()
        Task {
            do {
                let heard = try await speechToText.transcribe(wav: wav)
                if heard.isEmpty {
                    notice = "Didn't catch that. Hold ⌥ and try again."
                } else if let command = await acceptedCommand(from: heard, context: context) {
                    onCommand(command)
                }
            } catch {
                notice = error.localizedDescription
            }
            phase = .idle
        }
    }

    /// The command to send for what was heard, or nil to send nothing. Claude rewrites the words
    /// into the parser's terms; then every word must be in the game's vocabulary (answers to the
    /// game's questions, like a save file name, are exempt). If Claude can't be reached, what was
    /// heard still goes through only if the parser would accept it as is.
    private func acceptedCommand(from heard: String, context: CommandContext) async -> String? {
        var candidate = heard
        var cleanupFailure: String?
        if let interpreter {
            phase = .interpreting
            do {
                candidate = try await interpreter.interpret(heard, context: context)
                if candidate.isEmpty {
                    notice = "That didn't sound like a command: “\(heard)”"
                    return nil
                }
            } catch {
                cleanupFailure = "Command cleanup failed (\(error.localizedDescription))"
            }
        }
        let command = GameVocabulary.normalize(candidate)
        if !context.isAnsweringQuestion, let vocabulary {
            let unknown = vocabulary.unknownWords(in: command)
            guard unknown.isEmpty else {
                let words = unknown.map { "“\($0)”" }.joined(separator: ", ")
                notice = (cleanupFailure.map { $0 + ". " } ?? "")
                    + "Not sent: the game doesn't know \(words). Heard “\(heard)”"
                return nil
            }
        }
        if let cleanupFailure {
            notice = cleanupFailure + ", sent as heard"
        } else if command.caseInsensitiveCompare(GameVocabulary.normalize(heard)) != .orderedSame {
            notice = "Heard “\(heard)”"
        }
        return command
    }

    /// Discards the current recording without sending it.
    func cancel() {
        guard phase == .listening else { return }
        _ = recorder.stop()
        phase = .idle
    }

    /// ⌥ pressed on its own starts listening; releasing it sends. Typing a key while ⌥ is down
    /// (an ⌥-character or shortcut) cancels instead.
    private func handleKey(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
            if flags == .option, !optionKeyHeld, phase == .idle {
                optionKeyHeld = true
                begin()
            } else if optionKeyHeld, !flags.contains(.option) {
                optionKeyHeld = false
                end()
            }
        case .keyDown:
            if optionKeyHeld {
                optionKeyHeld = false
                cancel()
            }
        default:
            break
        }
    }

    private static let micDeniedMessage =
        "Microphone access is off. Turn it on in System Settings > Privacy & Security > Microphone."
}
