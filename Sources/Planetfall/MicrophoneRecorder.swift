import AVFoundation
import os

/// Records the default microphone as mono 16-bit samples at the device's own sample rate.
/// Fish accepts any WAV sample rate, so there's no resampling step.
///
/// Deliberately not main-actor isolated: the tap block runs on the audio thread, and a closure
/// formed inside a main-actor method would trap there under Swift 6.
final class MicrophoneRecorder: @unchecked Sendable {
    struct Recording {
        let samples: [Int16]
        let sampleRate: Int

        var duration: Double { sampleRate > 0 ? Double(samples.count) / Double(sampleRate) : 0 }
        var peak: Int16 { samples.lazy.map { $0 == .min ? .max : abs($0) }.max() ?? 0 }
    }

    enum RecorderError: LocalizedError {
        case noInputDevice

        var errorDescription: String? { "No microphone found." }
    }

    private let samples = OSAllocatedUnfairLock<[Int16]>(initialState: [])
    private var engine: AVAudioEngine?
    private var sampleRate = 0

    func start() throws {
        _ = stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInputDevice }

        let samples = self.samples
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let channelCount = Int(buffer.format.channelCount)
            let frames = Int(buffer.frameLength)
            var mono = [Int16](repeating: 0, count: frames)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channelCount { sum += channels[channel][frame] }
                let value = max(-1, min(1, sum / Float(channelCount)))
                mono[frame] = Int16(value * Float(Int16.max))
            }
            let chunk = mono
            samples.withLock { $0.append(contentsOf: chunk) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
        sampleRate = Int(format.sampleRate)
    }

    /// Stops recording and returns everything captured since `start()`.
    func stop() -> Recording {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        let captured = samples.withLock { buffer in
            defer { buffer.removeAll() }
            return buffer
        }
        return Recording(samples: captured, sampleRate: sampleRate)
    }
}
