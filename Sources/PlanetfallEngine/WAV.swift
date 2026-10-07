import Foundation

/// Mono 16-bit PCM WAV, the format voice commands are uploaded in.
public enum WAV {
    public static func encode(samples: [Int16], sampleRate: Int) -> Data {
        let dataSize = samples.count * MemoryLayout<Int16>.size
        var data = Data(capacity: 44 + dataSize)
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLittleEndian(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        data.appendLittleEndian(UInt32(16))              // fmt chunk size
        data.appendLittleEndian(UInt16(1))               // PCM
        data.appendLittleEndian(UInt16(1))               // mono
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * 2))  // bytes per second
        data.appendLittleEndian(UInt16(2))               // bytes per frame
        data.appendLittleEndian(UInt16(16))              // bits per sample
        data.append(contentsOf: Array("data".utf8))
        data.appendLittleEndian(UInt32(dataSize))
        samples.map(\.littleEndian).withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
