import AVFoundation

/// Plays one 16-bit mono PCM clip on a loop, for ambience under the voices. Volume is set by
/// the caller (fades included); stopping drops the loop.
///
/// Not main-actor isolated, like `PCMStreamPlayer`.
final class LoopPlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat

    init(sampleRate: Int) {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate),
                               channels: 1, interleaved: false)!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    var isPlaying: Bool { node.isPlaying }

    var volume: Float {
        get { node.volume }
        set { node.volume = newValue }
    }

    /// Starts looping `pcm` (16-bit little-endian samples) at the current volume.
    func play(_ pcm: Data) {
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
        if !engine.isRunning {
            engine.prepare()
            guard (try? engine.start()) != nil else { return }
        }
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: .loops)
        node.play()
    }

    func stop() {
        node.stop()
    }
}
