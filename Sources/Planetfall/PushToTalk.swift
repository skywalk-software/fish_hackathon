import AppKit
import AVFoundation
import PlanetfallEngine

/// Hold-to-talk voice commands. While ⌥ (or the mic button) is held, the microphone records;
/// on release the clip goes to Fish Audio speech-to-text and the transcript is handed back.
@MainActor
@Observable
final class PushToTalk {
    enum Phase: Equatable {
        case idle, listening, transcribing
    }

    private(set) var phase: Phase = .idle
    /// A hint or error to show the player. Cleared when the next recording starts.
    private(set) var notice: String?
    /// Why voice input is off (no API key), or nil when it's ready.
    let unavailableReason: String?

    @ObservationIgnored private let speechToText: FishSpeechToText?
    @ObservationIgnored private let recorder = MicrophoneRecorder()
    @ObservationIgnored private var canListen: () -> Bool = { false }
    @ObservationIgnored private var onTranscript: (String) -> Void = { _ in }
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
    }

    /// Starts listening for ⌥ and routes transcripts to `onTranscript`.
    func activate(canListen: @escaping () -> Bool, onTranscript: @escaping (String) -> Void) {
        self.canListen = canListen
        self.onTranscript = onTranscript
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
        Task {
            do {
                let text = try await speechToText.transcribe(wav: wav)
                if text.isEmpty {
                    notice = "Didn't catch that. Hold ⌥ and try again."
                } else {
                    onTranscript(text)
                }
            } catch {
                notice = error.localizedDescription
            }
            phase = .idle
        }
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
