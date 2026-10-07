import CryptoKit
import Foundation

public enum FishTextToSpeechError: LocalizedError {
    case http(status: Int, message: String?)
    case unreadableResponse

    public var errorDescription: String? {
        switch self {
        case .http(401, _):
            "Fish Audio rejected the API key. Check FISH_API_KEY in .env."
        case .http(402, _):
            "The Fish Audio account is out of API credit."
        case .http(429, _):
            "Fish Audio is at its concurrency limit."
        case .http(let status, let message):
            "Fish Audio text-to-speech failed (\(status))" + (message.map { ": \($0)" } ?? ".")
        case .unreadableResponse:
            "Fish Audio returned a response we couldn't read."
        }
    }
}

/// Speaks text in a Fish Audio voice (`POST /v1/tts`), streamed as raw PCM so playback can
/// start about half a second in instead of waiting for the whole line.
public struct FishTextToSpeech: Sendable {
    public static let endpoint = URL(string: "https://api.fish.audio/v1/tts")!
    /// Streamed audio is 16-bit little-endian mono PCM at this rate.
    public static let sampleRate = 24_000

    public let apiKey: String
    /// Sent as the `model` header. `s2.1-pro-free` costs nothing through 2026-11-30.
    public let model: String
    private let urlSession: URLSession

    public init(apiKey: String, model: String = "s2.1-pro-free", urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.urlSession = urlSession
    }

    /// The voice reading `text`, as PCM chunks of about `chunkBytes` (0.2 s by default).
    /// Cancelling the consuming task cancels the request.
    public func stream(_ text: String, voiceID: String, chunkBytes: Int = 9_600) -> AsyncThrowingStream<Data, Error> {
        let request = makeRequest(text: text, voiceID: voiceID)
        let urlSession = urlSession
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await urlSession.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw FishTextToSpeechError.unreadableResponse }
                    guard http.statusCode == 200 else {
                        var body = Data()
                        for try await byte in bytes where body.count < 4096 { body.append(byte) }
                        throw FishTextToSpeechError.http(status: http.statusCode, message: Self.errorMessage(in: body))
                    }
                    var chunk = Data(capacity: chunkBytes)
                    for try await byte in bytes {
                        chunk.append(byte)
                        if chunk.count >= chunkBytes {
                            continuation.yield(chunk)
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    if !chunk.isEmpty { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeRequest(text: String, voiceID: String) -> URLRequest {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(model, forHTTPHeaderField: "model")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "text": text,
            "reference_id": voiceID,
            "format": "pcm",
            "sample_rate": Self.sampleRate,
            // "balanced" starts audio in ~0.5 s; "normal" waited ~4 s for the first byte.
            "latency": "balanced",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    static func errorMessage(in body: Data) -> String? {
        struct ErrorBody: Decodable { let message: String? }
        return (try? JSONDecoder().decode(ErrorBody.self, from: body))?.message
    }
}

/// Finished lines saved as raw PCM, so a character repeating themselves plays instantly and
/// costs nothing. Keyed by model, voice, and exact text.
public struct VoiceLineCache: Sendable {
    public let directory: URL

    public static let `default` = VoiceLineCache(
        directory: URL.cachesDirectory.appendingPathComponent("Planetfall/Voices", isDirectory: true))

    public init(directory: URL) {
        self.directory = directory
    }

    public func load(text: String, voiceID: String, model: String) -> Data? {
        try? Data(contentsOf: fileURL(text: text, voiceID: voiceID, model: model))
    }

    public func store(_ pcm: Data, text: String, voiceID: String, model: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? pcm.write(to: fileURL(text: text, voiceID: voiceID, model: model), options: .atomic)
    }

    func fileURL(text: String, voiceID: String, model: String) -> URL {
        let key = [model, voiceID, String(FishTextToSpeech.sampleRate), text].joined(separator: "\n")
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".pcm")
    }
}
