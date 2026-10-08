import Foundation

/// What the narrator sees for one turn.
public struct NarrationContext: Equatable, Sendable {
    public var location: String?
    /// The player's command, or nil for the opening.
    public var command: String?
    /// What the game printed, with voiced characters' lines replaced by "[Name speaks]".
    public var output: String
    /// The narrator's last few lines, oldest first, so it doesn't repeat its phrasing.
    public var previousNarration: [String]

    public init(location: String?, command: String?, output: String, previousNarration: [String]) {
        self.location = location
        self.command = command
        self.output = output
        self.previousNarration = previousNarration
    }
}

/// Retells each turn's game output as a sentence or two of spoken narration, using Claude
/// (Messages API, SSE). Character lines are left to the characters' own voices.
public struct Narrator: Sendable {
    /// The reply when there's nothing to narrate beyond the characters' lines.
    public static let skipToken = "SKIP"

    public let apiKey: String
    public let model: String
    /// `output_config.effort`. Low keeps narration quick; Claude Opus 5.5 defaults to medium.
    public let effort: String?
    /// Retries refused requests on Anthropic's recommended fallback model (`fallbacks: "default"`).
    public let serverSideFallbacks: Bool
    private let urlSession: URLSession

    public init(apiKey: String, model: String = "claude-opus-5-5", effort: String? = "low",
                serverSideFallbacks: Bool = true, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.effort = effort
        self.serverSideFallbacks = serverSideFallbacks
        self.urlSession = urlSession
    }

    /// Streams the narration a sentence at a time, so each sentence can be spoken while the next
    /// is written. Finishes without yielding when Claude skips the turn.
    public func sentences(for context: NarrationContext) -> AsyncThrowingStream<String, Error> {
        let urlSession = urlSession
        let request = Result { try makeRequest(context: context) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await urlSession.bytes(for: request.get())
                    guard let http = response as? HTTPURLResponse else { throw CommandInterpreterError.unreadableResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        throw Commentator.httpError(body, statusCode: http.statusCode)
                    }
                    var filter = NarrationFilter()
                    var usage = TokenUsage()
                    defer { ClaudeUsageLedger.shared.record(.narration, usage) }
                    for try await line in bytes.lines {
                        if let output = Commentator.outputTokens(in: line) { usage.output = output }
                        switch try Commentator.parseEvent(line) {
                        case .usage(let start):
                            usage = TokenUsage(input: start.input, cacheRead: start.cacheRead,
                                               cacheWrite: start.cacheWrite, output: max(usage.output, start.output))
                        case .text(let delta):
                            for sentence in filter.feed(delta) { continuation.yield(sentence) }
                        case .stop(let reason):
                            if reason == "refusal" { throw CommandInterpreterError.refused }
                        case nil:
                            break
                        }
                    }
                    for sentence in filter.finish() { continuation.yield(sentence) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeRequest(context: NarrationContext) throws -> URLRequest {
        var request = URLRequest(url: Commentator.endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var body: [String: Any] = [
            "model": model,
            // Thinking counts toward this too, so leave room beyond the one or two sentences.
            "max_tokens": 4096,
            "stream": true,
            // The instructions never change, so they're cached; the turn goes in the user message.
            "system": [["type": "text", "text": Self.systemPrompt, "cache_control": ["type": "ephemeral"]]],
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

    static let systemPrompt = """
        You are the narrator of Planetfall, Infocom's 1983 comedic science-fiction text adventure, \
        read aloud for a player who is listening rather than reading. The player is a lowly Ensign \
        Seventh Class in the Stellar Patrol.

        Each turn you get the text the game printed after the player's command. Retell it as spoken \
        narration of the surroundings and what just happened.

        Rules:
        - One or two sentences, at most about 40 words. It is spoken aloud, so plain text only: no \
        markdown, lists, emoji, or quotation marks.
        - Second person, present tense: "You step into a narrow corridor..."
        - Keep what matters for play: where the player is, notable objects, exits, and what changed. \
        Use only what the game text says. Never invent rooms, objects, exits, or events, and never \
        hint at puzzle solutions.
        - Characters speak for themselves. Their lines are replaced by markers like [Floyd speaks] and \
        are played in their own voices right after you. Say who speaks or how ("Blather glares at you, \
        arms crossed"), never what they say, and don't read the markers aloud.
        - Short replies get short narration: "Taken." becomes "Got it." Parser complaints ("I don't \
        know the word...") become a brief, wry in-world line.
        - Skip the game's title and copyright banner.
        - You're read aloud by a warm, lively voice actor. Start each sentence with one short delivery \
        tag in square brackets that tells them how to say it, like [warm], [wry], [amused], [hushed], \
        [urgent], [ominous], or [deadpan]. Match the moment, and vary them. A SKIP gets no tag.
        - Vary your phrasing from your previous lines.
        - If nothing is left to narrate once the character lines are set aside, reply with exactly \
        \(skipToken) and nothing else.
        """

    static func userMessage(context: NarrationContext) -> String {
        let previous = context.previousNarration.isEmpty
            ? "(none yet)"
            : context.previousNarration.map { "- \($0)" }.joined(separator: "\n")
        return """
            Room: \(context.location ?? "unknown")
            Player's command: \(context.command.map { "> \($0)" } ?? "(the game is starting)")

            What the game printed:
            <game_output>
            \(context.output)
            </game_output>

            Your previous lines, oldest first:
            <previous_narration>
            \(previous)
            </previous_narration>

            Your narration (or \(skipToken)):
            """
    }
}

/// Turns streamed narration text into sentences for TTS. Holds back a reply that might be the
/// skip token, and joins very short sentences ("Got it.") with the next so each TTS request
/// has enough text to sound natural.
struct NarrationFilter {
    private var held = ""
    private var decided = false
    private var buffer = ""

    /// Shorter sentences wait for the next one.
    static let minimumSentenceLength = 25

    mutating func feed(_ delta: String) -> [String] {
        guard decided else {
            held += delta
            // Decide on the words, not delivery tags, and wait while a tag is being written.
            if DeliveryTags.hasOpenTag(held) { return [] }
            let words = DeliveryTags.strip(held)
            if words.isEmpty || Narrator.skipToken.hasPrefix(words) { return [] }
            decided = true
            return append(held)
        }
        return append(delta)
    }

    mutating func finish() -> [String] {
        if !decided {
            let words = DeliveryTags.strip(held)
            guard !words.isEmpty, words.trimmingCharacters(in: .punctuationCharacters) != Narrator.skipToken else {
                return []
            }
            decided = true
            _ = append(held)
        }
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? [] : [rest]
    }

    /// Adds text and returns any sentences now complete: ending in . ! or ? and followed by a space.
    private mutating func append(_ text: String) -> [String] {
        buffer += text
        var sentences: [String] = []
        var searchStart = buffer.startIndex
        while let match = buffer[searchStart...].firstMatch(of: /[.!?]+["')\]]*\s+/) {
            let sentence = buffer[..<match.range.upperBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count >= Self.minimumSentenceLength {
                sentences.append(sentence)
                buffer = String(buffer[match.range.upperBound...])
                searchStart = buffer.startIndex
            } else {
                searchStart = match.range.upperBound
            }
        }
        return sentences
    }
}
