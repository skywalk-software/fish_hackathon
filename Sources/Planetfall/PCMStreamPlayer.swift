import AVFoundation

/// Plays 16-bit mono PCM as it arrives, chunk by chunk, so a streamed TTS line starts before
/// it's fully downloaded. Chunks queue up and play back-to-back.
///
/// Not main-actor isolated, for the same reason as `MicrophoneRecorder`: buffer completion
/// handlers run on the audio thread.
final class PCMStreamPlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat
    /// Where the last queued sample ends, in the player node's sample time. Guarded by `lock`.
    private var scheduledEnd: Int64 = 0
    private let lock = NSLock()

    init(sampleRate: Int) {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate),
                               channels: 1, interleaved: false)!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    /// Queues `pcm` (16-bit little-endian samples) after anything already playing.
    func enqueue(_ pcm: Data) {
        let frames = pcm.count / 2
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        pcm.withUnsafeBytes { raw in
            for frame in 0..<frames {
                let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: frame * 2, as: Int16.self))
                samples[frame] = Float(sample) / 32_768
            }
        }
        guard startIfNeeded() else { return }
        lock.withLock {
            // If the queue ran dry, new audio starts now rather than after the old end.
            scheduledEnd = max(scheduledEnd, playedFrames) + Int64(frames)
        }
        node.scheduleBuffer(buffer)
    }

    /// Seconds of queued audio that haven't played yet (0 when idle).
    var secondsRemaining: Double {
        lock.withLock { Double(max(0, scheduledEnd - playedFrames)) / format.sampleRate }
    }

    /// Samples played since the node last started.
    private var playedFrames: Int64 {
        guard node.isPlaying, let renderTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: renderTime) else { return 0 }
        return playerTime.sampleTime
    }

    /// Returns once everything queued so far has played, or playback is stopped.
    func waitUntilPlayed() async {
        guard node.isPlaying, let marker = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) else { return }
        marker.frameLength = 1
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Called after the marker plays, or immediately when stop() flushes the queue.
            node.scheduleBuffer(marker, completionCallbackType: .dataPlayedBack) { @Sendable _ in
                continuation.resume()
            }
        }
    }

    /// Cuts off playback and drops anything queued.
    func stop() {
        node.stop()
        lock.withLock { scheduledEnd = 0 }
    }

    private func startIfNeeded() -> Bool {
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return false }
        }
        if !node.isPlaying { node.play() }
        return true
    }
}
