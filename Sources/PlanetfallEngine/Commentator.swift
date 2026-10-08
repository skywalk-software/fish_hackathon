import Foundation

/// What the commentator sees each turn: the game so far and what it has already said.
public struct CommentaryContext: Equatable, Sendable {
    public var location: String?
    public var score: Int?
    /// Planetfall's "Moves" status field, which is really the ship's clock (it starts around 4450).
    public var moves: Int?
    /// How many commands the player has entered: the real measure of how long they've played.
    public var turnsPlayed: Int?
    /// The end of the transcript, oldest first, with commands written as "> command".
    public var recentOutput: String
    /// The commentator's own recent lines, oldest first, so it doesn't repeat its jokes.
    public var previousLines: [String]
    /// Achievements the player earned on this turn, for the commentator to award.
    public var newAchievements: [Achievement] = []

    public init(location: String?, score: Int?, moves: Int?, turnsPlayed: Int? = nil,
                recentOutput: String, previousLines: [String], newAchievements: [Achievement] = []) {
        self.newAchievements = newAchievements
        self.location = location
        self.score = score
        self.moves = moves
        self.turnsPlayed = turnsPlayed
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
                    var usage = TokenUsage()
                    // Recorded however the stream ends, since a cut-off response is still billed.
                    defer { ClaudeUsageLedger.shared.record(.commentary, usage) }
                    for try await line in bytes.lines {
                        if let output = Self.outputTokens(in: line) { usage.output = output }
                        switch try Self.parseEvent(line) {
                        case .usage(let start):
                            usage = TokenUsage(input: start.input, cacheRead: start.cacheRead,
                                               cacheWrite: start.cacheWrite, output: max(usage.output, start.output))
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
        You are \(persona.name), \(persona.description)

        Right now you're co-hosting a let's-play: a person is playing Planetfall, Infocom's 1983 comedic \
        science-fiction text adventure, and you're watching over their shoulder and reacting live, like a \
        streamer's sidekick. You are outside the game. You can't be seen or heard by anyone in it, you \
        can't act in it, and you never pretend to be there. In the game, the player controls a lowly \
        Ensign Seventh Class in the Stellar Patrol; when you mention that character, call them the \
        player's ensign, or address the player as "you" when talking about their choices.

        Your personality: \(persona.personality)

        Each turn you get the recent game output and the player's latest command. React to that latest \
        command and what happened because of it, with one quip. Comment like a viewer: on the player's \
        choices and luck, the game's events and characters, and the delights and indignities of playing \
        a 1983 text adventure (the parser, typing every command, dying in a single sentence).

        Rules:
        - One or two short sentences, at most about 30 words. It is spoken aloud and shown in a \
        caption, so plain text only: no markdown, emoji, hashtags, quotation marks around the whole \
        line, or stage directions like *sighs*.
        - React to what actually happened in the game output. Never invent events, items, rooms, or \
        characters that the output doesn't show.
        - Never spoil puzzles, hint at solutions, or say what's coming next. You can mock a failed \
        attempt, not explain the fix.
        - Roast the play, not the person: tease their choices, never anything about who they are. \
        Playful, never cruel. Keep it PG-13.
        - Your line is read aloud by a voice actor. Start it with one delivery tag in square brackets \
        that tells them how to say it, like [dripping with sarcasm], [theatrically weary], \
        [mock-impressed], [deadpan], or [barely suppressing a laugh]; you may add one more before a \
        later sentence. At most two tags, and pick ones that fit the moment. Tags are removed from \
        the caption, so never put words the player should read inside brackets. A PASS gets no tag.
        - Vary your material. Don't reuse a joke, opener, or catchphrase from your previous lines.
        - Sometimes the app tells you the player just earned an achievement. Then award it: work \
        the achievement's name into your reaction to what just happened, in your own words and \
        your own attitude, still within the length limit. If it came with a new Dock icon, \
        mention that too. Never pass on an achievement turn.
        - If the latest turn is routine and you have nothing good to say (a repeated look, checking \
        inventory again, waiting with nothing happening), reply with exactly \(Commentator.passToken) \
        and nothing else. Pass on roughly a third of turns so the commentary stays punchy.
        """
    }

    static func userMessage(context: CommentaryContext) -> String {
        var status = "Room: \(context.location ?? "unknown")"
        if let score = context.score { status += " | Score: \(score)" }
        if let turns = context.turnsPlayed { status += " | Commands entered so far: \(turns)" }
        // The game labels its clock "Moves"; say what it is so it isn't mistaken for a turn count.
        if let moves = context.moves { status += " | Ship's clock (in-game time, not a turn count): \(moves)" }
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

            \(achievementBlock(context.newAchievements))Your reaction to the latest turn (or \(passToken)):
            """
    }

    /// Tells the commentator about achievements earned this turn, or nothing if there are none.
    static func achievementBlock(_ achievements: [Achievement]) -> String {
        guard !achievements.isEmpty else { return "" }
        let lines = achievements.map { achievement in
            var line = "- \(achievement.title): \(achievement.description)"
            if achievement.unlocksIcon != nil {
                line += " It also unlocks a new Dock icon for the app, the player's own "
                    + "Ensign Seventh Class portrait, which they can choose in Settings."
            }
            return line
        }.joined(separator: "\n")
        return """
            The player just earned \(achievements.count == 1 ? "an achievement" : "achievements") \
            on this turn. Award it in your reaction (don't pass):
            <achievement_unlocked>
            \(lines)
            </achievement_unlocked>


            """
    }

    // MARK: - Server-sent events

    enum StreamEvent: Equatable {
        /// The tokens a message started with (input and cache), from `message_start`.
        case usage(TokenUsage)
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
        case "message_start":
            return event.message?.usage.map { .usage($0.tokenUsage) }
        case "content_block_delta" where event.delta?.type == "text_delta":
            return event.delta?.text.map(StreamEvent.text)
        case "message_delta":
            // Its output-token count is read separately, with `outputTokens(in:)`.
            return .stop(reason: event.delta?.stop_reason)
        case "error":
            throw CommandInterpreterError.http(status: 200, type: event.error?.type, message: event.error?.message)
        default:
            return nil
        }
    }

    /// The output tokens reported on a `message_delta` line, if it has any.
    static func outputTokens(in line: String) -> Int? {
        guard line.hasPrefix("data:") else { return nil }
        let json = Data(line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces).utf8)
        guard let event = try? JSONDecoder().decode(SSEEvent.self, from: json), event.type == "message_delta" else { return nil }
        return event.usage?.output_tokens
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
        struct Message: Decodable { let usage: Usage? }
        let type: String?
        let delta: Delta?
        let error: ErrorDetail?
        let message: Message?
        let usage: Usage?
    }

    /// The `usage` object on Messages API responses and stream events.
    struct Usage: Decodable {
        let input_tokens: Int?
        let cache_read_input_tokens: Int?
        let cache_creation_input_tokens: Int?
        let output_tokens: Int?

        var tokenUsage: TokenUsage {
            TokenUsage(input: input_tokens ?? 0, cacheRead: cache_read_input_tokens ?? 0,
                       cacheWrite: cache_creation_input_tokens ?? 0, output: output_tokens ?? 0)
        }
    }

    /// Holds back the start of the reply until it's clear it isn't the pass token, so
    /// "PASS" never flashes on screen.
    struct PassFilter {
        private var held = ""
        private var decided = false

        mutating func feed(_ delta: String) -> String? {
            if decided { return delta }
            held += delta
            // Decide on the words, not delivery tags ("[deadpan] PASS" is still a pass), and
            // wait while a tag is still being written.
            if DeliveryTags.hasOpenTag(held) { return nil }
            let words = DeliveryTags.strip(held)
            if words.isEmpty || Commentator.passToken.hasPrefix(words) { return nil }
            decided = true
            return held
        }

        /// Anything still held at the end of the stream, unless it was the pass token.
        mutating func finish() -> String? {
            guard !decided else { return nil }
            let words = DeliveryTags.strip(held).trimmingCharacters(in: .punctuationCharacters)
            return words.isEmpty || words == Commentator.passToken ? nil : held
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
        description: "a jaded retro-gaming commentary robot who lives on a cluttered streaming desk, "
            + "surrounded by old floppy disks, game boxes, and a cold cup of coffee it can't drink. It has watched "
            + "thousands of people play classic games and has opinions about all of them.",
        personality: "Dry, deadpan, and unimpressed, with the weary confidence of a machine that has seen "
            + "every possible way to fail a text adventure. Loves a callback to the player's earlier blunders. "
            + "Secretly roots for the player and lets it slip when they do something genuinely clever, then "
            + "immediately covers it up.",
        artID: "sidekick"
    )
}
