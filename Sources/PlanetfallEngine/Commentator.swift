import Foundation

/// What the commentator sees each turn: the game so far and what it has already said.
public struct CommentaryContext: Equatable, Sendable {
    public var location: String?
    public var score: Int?
    public var moves: Int?
    /// The end of the transcript, oldest first, with commands written as "> command".
    public var recentOutput: String
    /// The commentator's own recent lines, oldest first, so it doesn't repeat its jokes.
    public var previousLines: [String]

    public init(location: String?, score: Int?, moves: Int?, recentOutput: String, previousLines: [String]) {
        self.location = location
        self.score = score
        self.moves = moves
        self.recentOutput = recentOutput
        self.previousLines = previousLines
    }
}

/// Streams a let's-play style quip about the latest turn from Claude (Messages API, SSE).
/// Swift has no official Anthropic SDK, so this speaks HTTP directly, like `CommandInterpreter`.
public struct Commentator: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// The reply the model gives when a turn isn't worth a comment.
    public static let passToken = "PASS"

    public let apiKey: String
    public let persona: SidekickPersona
    public let model: String
    /// `output_config.effort`. Low keeps the quip quick; it's banter, not a puzzle.
    public let effort: String?
    /// Retries refused requests on Anthropic's recommended fallback model (`fallbacks: "default"`).
    public let serverSideFallbacks: Bool
    private let urlSession: URLSession

    public init(apiKey: String, persona: SidekickPersona = .default, model: String = "claude-opus-5-5",
                effort: String? = "low", serverSideFallbacks: Bool = true, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.persona = persona
        self.model = model
        self.effort = effort
        self.serverSideFallbacks = serverSideFallbacks
        self.urlSession = urlSession
    }

    /// Streams the quip's text as it's generated. Finishes without yielding anything when
    /// the model passes on the turn or declines.
    public func commentary(on context: CommentaryContext) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await urlSession.bytes(for: makeRequest(context: context))
                    guard let http = response as? HTTPURLResponse else { throw CommandInterpreterError.unreadableResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        throw Self.httpError(body, statusCode: http.statusCode)
                    }
                    var filter = PassFilter()
                    for try await line in bytes.lines {
                        switch try Self.parseEvent(line) {
                        case .text(let delta):
                            if let visible = filter.feed(delta) { continuation.yield(visible) }
                        case .stop(let reason):
                            // A refusal can arrive mid-stream; anything shown so far stays.
                            if reason == "refusal" { throw CommandInterpreterError.refused }
                        case nil:
                            break
                        }
                    }
                    if let visible = filter.finish() { continuation.yield(visible) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeRequest(context: CommentaryContext) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var body: [String: Any] = [
            "model": model,
            // Thinking counts toward this too, so leave room beyond the one or two sentences.
            "max_tokens": 4096,
            "stream": true,
            // The persona never changes, so it's cached; the game state goes in the user turn.
            "system": [["type": "text", "text": systemPrompt, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": Self.userMessage(context: context)]],
        ]
        if let effort { body["output_config"] = ["effort": effort] }
        if serverSideFallbacks {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    var systemPrompt: String {
        """
        You are \(persona.name), \(persona.description) You are co-hosting a let's-play of Planetfall, \
        Infocom's 1983 comedic science-fiction text adventure, reacting live to what the player does, \
        like a streamer's sidekick. The player is a lowly Ensign Seventh Class in the Stellar Patrol.

        Your personality: \(persona.personality)

        Each turn you get the recent game output and the player's latest command. React to that \
        latest command and what happened because of it, with one quip.

        Rules:
        - One or two short sentences, at most about 30 words. It is spoken aloud and shown in a \
        caption, so plain text only: no markdown, emoji, hashtags, quotation marks around the whole \
        line, or stage directions like *sighs*.
        - React to what actually happened in the game output. Never invent events, items, rooms, or \
        characters that the output doesn't show.
        - Never spoil puzzles, hint at solutions, or say what's coming next. You can mock a failed \
        attempt, not explain the fix.
        - Tease the player, not the person: playful roast, never cruel, nothing about real-world \
        identity. Keep it PG-13.
        - Vary your material. Don't reuse a joke, opener, or catchphrase from your previous lines.
        - If the latest turn is routine and you have nothing good to say (a repeated look, checking \
        inventory again, waiting with nothing happening), reply with exactly \(Commentator.passToken) \
        and nothing else. Pass on roughly a third of turns so the commentary stays punchy.
        """
    }

    static func userMessage(context: CommentaryContext) -> String {
        var status = "Room: \(context.location ?? "unknown")"
        if let score = context.score { status += " | Score: \(score)" }
        if let moves = context.moves { status += " | Moves: \(moves)" }
        let previous = context.previousLines.isEmpty
            ? "(none yet)"
            : context.previousLines.map { "- \($0)" }.joined(separator: "\n")
        return """
            \(status)

            Recent game output, oldest first. The last command and the text after it are what just happened:
            <game_output>
            \(context.recentOutput)
            </game_output>

            Your previous lines, oldest first:
            <previous_lines>
            \(previous)
            </previous_lines>

            Your reaction to the latest turn (or \(passToken)):
            """
    }

    // MARK: - Server-sent events

    enum StreamEvent: Equatable {
        case text(String)
        case stop(reason: String?)
    }

    /// Parses one SSE line. Only text deltas and the stop reason matter here; thinking and
    /// fallback blocks are skipped.
    static func parseEvent(_ line: String) throws -> StreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let json = Data(line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces).utf8)
        guard let event = try? JSONDecoder().decode(SSEEvent.self, from: json) else { return nil }
        switch event.type {
        case "content_block_delta" where event.delta?.type == "text_delta":
            return event.delta?.text.map(StreamEvent.text)
        case "message_delta":
            return .stop(reason: event.delta?.stop_reason)
        case "error":
            throw CommandInterpreterError.http(status: 200, type: event.error?.type, message: event.error?.message)
        default:
            return nil
        }
    }

    static func httpError(_ body: Data, statusCode: Int) -> CommandInterpreterError {
        let error = (try? JSONDecoder().decode(SSEEvent.self, from: body))?.error
        return .http(status: statusCode, type: error?.type, message: error?.message)
    }

    private struct SSEEvent: Decodable {
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let stop_reason: String?
        }
        struct ErrorDetail: Decodable {
            let type: String?
            let message: String?
        }
        let type: String?
        let delta: Delta?
        let error: ErrorDetail?
    }

    /// Holds back the start of the reply until it's clear it isn't the pass token, so
    /// "PASS" never flashes on screen.
    struct PassFilter {
        private var held = ""
        private var decided = false

        mutating func feed(_ delta: String) -> String? {
            if decided { return delta }
            held += delta
            let trimmed = held.trimmingCharacters(in: .whitespacesAndNewlines)
            // Still could be the pass token: keep waiting.
            if Commentator.passToken.hasPrefix(trimmed) || trimmed == Commentator.passToken { return nil }
            decided = true
            return held.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : held
        }

        /// Anything still held at the end of the stream, unless it was the pass token.
        mutating func finish() -> String? {
            guard !decided else { return nil }
            let trimmed = held.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed == Commentator.passToken ? nil : held
        }
    }
}

/// Who the sidekick is. Change `.default` to recast them.
public struct SidekickPersona: Equatable, Sendable {
    public var name: String
    /// Completes "You are <name>, …".
    public var description: String
    public var personality: String
    /// Art/NPCs/<artID>.jpg is used as their avatar if it exists.
    public var artID: String

    public init(name: String, description: String, personality: String, artID: String) {
        self.name = name
        self.description = description
        self.personality = personality
        self.artID = artID
    }

    public static let `default` = SidekickPersona(
        name: "SNARK-9",
        description: "a decommissioned Stellar Patrol training drone with a cracked lens and a bad attitude, "
            + "who was supposed to grade ensigns and now heckles them instead.",
        personality: "Dry, deadpan, and unimpressed, with the weary confidence of a machine that has watched "
            + "a thousand ensigns fail. Loves a callback to the player's earlier blunders. Secretly roots for "
            + "the player and lets it slip when they do something genuinely clever, then immediately covers it up.",
        artID: "sidekick"
    )
}
