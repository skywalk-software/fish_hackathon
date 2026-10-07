import Foundation

public enum FishSpeechToTextError: LocalizedError {
    case http(status: Int, message: String?)
    case unreadableResponse

    public var errorDescription: String? {
        switch self {
        case .http(401, _):
            "Fish Audio rejected the API key. Check FISH_API_KEY in .env."
        case .http(402, _):
            "The Fish Audio account is out of API credit."
        case .http(429, _):
            "Fish Audio is at its concurrency limit. Try again in a moment."
        case .http(let status, let message):
            "Fish Audio speech-to-text failed (\(status))" + (message.map { ": \($0)" } ?? ".")
        case .unreadableResponse:
            "Fish Audio returned a response we couldn't read."
        }
    }
}

/// Transcribes one spoken command with Fish Audio speech-to-text (`POST /v1/asr`).
/// Fish's ASR only takes whole clips (no streaming), so push-to-talk sends one clip per command.
public struct FishSpeechToText: Sendable {
    public static let endpoint = URL(string: "https://api.fish.audio/v1/asr")!

    public let apiKey: String
    /// Sent as the `model` header: `transcribe-1-pro` (recommended) or `transcribe-1`.
    public let model: String
    /// ISO 639-1 hint such as "en". Fish still detects the language either way.
    public let language: String?
    private let urlSession: URLSession

    public init(apiKey: String, model: String = "transcribe-1-pro", language: String? = "en",
                urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.language = language
        self.urlSession = urlSession
    }

    /// Returns the command as plain text, or "" if no speech was recognized.
    public func transcribe(wav: Data) async throws -> String {
        let (data, response) = try await urlSession.data(for: makeRequest(audio: wav))
        guard let http = response as? HTTPURLResponse else { throw FishSpeechToTextError.unreadableResponse }
        return try Self.decode(data, statusCode: http.statusCode)
    }

    func makeRequest(audio: Data, boundary: String = "planetfall-\(UUID().uuidString)") -> URLRequest {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(model, forHTTPHeaderField: "model")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var fields = [("ignore_timestamps", "true")]
        if let language { fields.append(("language", language)) }
        // Pro-only field: drop cues like [laughter] so they never reach the game's parser.
        if model == "transcribe-1-pro" { fields.append(("tag_audio_events", "false")) }

        var body = Data()
        for (name, value) in fields {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"command.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n")
        request.httpBody = body
        return request
    }

    static func decode(_ data: Data, statusCode: Int) throws -> String {
        guard (200..<300).contains(statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.message
            throw FishSpeechToTextError.http(status: statusCode, message: message)
        }
        guard let body = try? JSONDecoder().decode(ResponseBody.self, from: data) else {
            throw FishSpeechToTextError.unreadableResponse
        }
        return cleanTranscript(body.text)
    }

    /// Turns "<|speaker:0|> Open the pod." into "Open the pod": drops speaker markers (sent even
    /// for one speaker), bracketed cues, and end punctuation the game's parser doesn't need.
    static func cleanTranscript(_ text: String) -> String {
        text.replacing(/<\|[^|>]*\|>/, with: " ")
            .replacing(/\[[^\]]*\]/, with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?。！？").union(.whitespaces))
    }

    private struct ResponseBody: Decodable {
        let text: String
    }

    private struct ErrorBody: Decodable {
        let message: String?
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(contentsOf: Array(string.utf8))
    }
}
