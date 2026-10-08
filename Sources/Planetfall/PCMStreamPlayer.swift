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
    /// Queued audio that hasn't finished playing, tagged with whose it is (a segment, e.g. one
    /// speaker's line), so one segment can be skipped. Guarded by `lock`.
    private var scheduled: [(segment: Int, buffer: AVAudioPCMBuffer, end: Int64)] = []
    private let lock = NSLock()

    init(sampleRate: Int) {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate),
                               channels: 1, interleaved: false)!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    /// Queues `pcm` (16-bit little-endian samples) after anything already playing. `segment`
    /// says whose audio it is, for `skip(segment:)`.
    func enqueue(_ pcm: Data, segment: Int = 0) {
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
        lock.withLock { schedule(buffer, segment: segment) }
    }

    /// Schedules a buffer and records where it ends. Call with `lock` held.
    private func schedule(_ buffer: AVAudioPCMBuffer, segment: Int) {
        let played = playedFrames
        // If the queue ran dry, new audio starts now rather than after the old end.
        scheduledEnd = max(scheduledEnd, played) + Int64(buffer.frameLength)
        scheduled.removeAll { $0.end <= played }
        scheduled.append((segment, buffer, scheduledEnd))
        node.scheduleBuffer(buffer)
    }

    /// The segment whose audio is playing right now, or nil when nothing is.
    var audibleSegment: Int? {
        lock.withLock {
            let played = playedFrames
            return scheduled.first { $0.end > played }?.segment
        }
    }

    /// Drops a segment's audio, keeping anything queued for other segments. Returns whether
    /// any of its audio was still waiting to play.
    @discardableResult
    func skip(segment: Int) -> Bool {
        lock.withLock {
            let played = playedFrames
            let pending = scheduled.filter { $0.end > played }
            guard pending.contains(where: { $0.segment == segment }) else { return false }
            // The node can't unschedule one buffer, so flush everything and requeue the rest.
            node.stop()
            scheduledEnd = 0
            scheduled = []
            let keep = pending.filter { $0.segment != segment }
            if !keep.isEmpty {
                node.play()
                for item in keep { schedule(item.buffer, segment: item.segment) }
            }
            return true
        }
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
        lock.withLock {
            scheduledEnd = 0
            scheduled = []
        }
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
