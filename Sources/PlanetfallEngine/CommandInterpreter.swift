import Foundation

public enum CommandInterpreterError: LocalizedError {
    case http(status: Int, type: String?, message: String?)
    case refused
    case incomplete(stopReason: String?)
    case unreadableResponse

    public var errorDescription: String? {
        switch self {
        case .http(401, _, _):
            "Anthropic rejected the API key. Check ANTHROPIC_API_KEY in .env."
        case .http(429, _, _):
            "Claude is rate limited. Try again in a moment."
        case .http(529, _, _):
            "Claude is overloaded. Try again in a moment."
        case .http(let status, _, let message):
            "Claude request failed (\(status))" + (message.map { ": \($0)" } ?? ".")
        case .refused:
            "Claude declined to interpret that."
        case .incomplete(let stopReason):
            "Claude's reply was cut off (\(stopReason ?? "no stop reason"))."
        case .unreadableResponse:
            "Claude returned a response we couldn't read."
        }
    }
}

/// What the game showed when the player spoke. Claude uses it to fix misheard nouns and to
/// answer the game's own questions (yes/no, save file names).
public struct CommandContext: Equatable, Sendable {
    public var location: String?
    /// The end of the transcript, oldest first, with commands written as "> command".
    public var recentOutput: String
    /// True when the game asked a question (like a save file name) instead of waiting at `>`,
    /// so the answer can be any word, not just parser vocabulary.
    public var isAnsweringQuestion: Bool

    public init(location: String?, recentOutput: String, isAnsweringQuestion: Bool = false) {
        self.location = location
        self.recentOutput = recentOutput
        self.isAnsweringQuestion = isAnsweringQuestion
    }

    /// The newest transcript entries that fit in about `maxCharacters`.
    public static func recent(_ entries: [TranscriptEntry], location: String?, maxCharacters: Int = 3000) -> CommandContext {
        var lines: [String] = []
        var used = 0
        for entry in entries.reversed() {
            var line: String
            switch entry {
            case .narration(_, let text), .system(_, let text): line = text
            case .command(_, let text): line = "> \(text)"
            }
            if used + line.count > maxCharacters {
                guard lines.isEmpty else { break }
                line = String(line.suffix(maxCharacters))
            }
            lines.append(line)
            used += line.count + 1
        }
        return CommandContext(location: location, recentOutput: lines.reversed().joined(separator: "\n"))
    }
}

extension GameSession {
    /// The current room and recent transcript, for interpreting a spoken command.
    public func commandContext() -> CommandContext {
        var context = CommandContext.recent(transcript, location: status?.location)
        context.isAnsweringQuestion = prompt == .question
        return context
    }
}

/// Turns what the player said into one line for Planetfall's parser, using Claude (Messages API).
/// Speech-to-text hears "um, could you pick up the kid"; the parser wants "take kit".
public struct CommandInterpreter: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public let apiKey: String
    public let model: String
    /// `output_config.effort`. Low keeps latency down for a short translation task.
    /// Pass nil for models that don't take effort (Claude Haiku 4.5).
    public let effort: String?
    /// Retries refused requests on Anthropic's recommended fallback model (`fallbacks: "default"`).
    /// Turn off for models outside the Claude Opus 5 family.
    public let serverSideFallbacks: Bool
    private let urlSession: URLSession

    /// The game parser's words (`GameVocabulary.words`). Given to Claude so commands use only
    /// words the game knows.
    public let vocabulary: [String]?

    public init(apiKey: String, model: String = "claude-opus-5-5", effort: String? = "low",
                serverSideFallbacks: Bool = true, vocabulary: [String]? = nil, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.effort = effort
        self.serverSideFallbacks = serverSideFallbacks
        self.vocabulary = vocabulary
        self.urlSession = urlSession
    }

    /// Returns the command to send to the game, or "" if the player wasn't giving it one.
    public func interpret(_ heard: String, context: CommandContext) async throws -> String {
        let (data, response) = try await urlSession.data(for: makeRequest(heard: heard, context: context))
        guard let http = response as? HTTPURLResponse else { throw CommandInterpreterError.unreadableResponse }
        return try Self.decode(data, statusCode: http.statusCode)
    }

    func makeRequest(heard: String, context: CommandContext) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var outputConfig: [String: Any] = ["format": ["type": "json_schema", "schema": Self.outputSchema]]
        if let effort { outputConfig["effort"] = effort }
        var body: [String: Any] = [
            "model": model,
            // Thinking counts toward this too, so leave room beyond the one-line answer.
            "max_tokens": 4096,
            // The instructions and vocabulary never change, so they're cached; the game state goes in
            // the user turn.
            "system": systemBlocks,
            "messages": [["role": "user", "content": Self.userMessage(heard: heard, context: context)]],
            "output_config": outputConfig,
        ]
        if serverSideFallbacks {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    static func userMessage(heard: String, context: CommandContext) -> String {
        """
        Current room: \(context.location ?? "unknown")

        Recent game output, oldest first:
        <game_output>
        \(context.recentOutput)
        </game_output>

        The player said: \(heard)
        """
    }

    static func decode(_ data: Data, statusCode: Int) throws -> String {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard (200..<300).contains(statusCode) else {
            let error = (try? decoder.decode(ErrorBody.self, from: data))?.error
            throw CommandInterpreterError.http(status: statusCode, type: error?.type, message: error?.message)
        }
        guard let message = try? decoder.decode(MessageBody.self, from: data) else {
            throw CommandInterpreterError.unreadableResponse
        }
        // A refused or cut-off reply may not match the schema, so check why it stopped first.
        switch message.stopReason {
        case "end_turn": break
        case "refusal": throw CommandInterpreterError.refused
        default: throw CommandInterpreterError.incomplete(stopReason: message.stopReason)
        }
        // Content can also hold thinking blocks; the structured output is the text block.
        guard let text = message.content.first(where: { $0.type == "text" })?.text,
              let output = try? decoder.decode(Output.self, from: Data(text.utf8)) else {
            throw CommandInterpreterError.unreadableResponse
        }
        return output.command
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static var outputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "command": [
                    "type": "string",
                    "description": "The line to type into the game, or an empty string if the player wasn't giving it a command.",
                ],
            ],
            "required": ["command"],
            "additionalProperties": false,
        ]
    }

    /// The instructions, then the vocabulary if there is one. The cache breakpoint goes on the
    /// last block so both are cached together.
    var systemBlocks: [[String: Any]] {
        var texts = [Self.systemPrompt]
        if let vocabulary, !vocabulary.isEmpty { texts.append(Self.vocabularyPrompt(vocabulary)) }
        return texts.enumerated().map { index, text in
            var block: [String: Any] = ["type": "text", "text": text]
            if index == texts.count - 1 { block["cache_control"] = ["type": "ephemeral"] }
            return block
        }
    }

    static func vocabularyPrompt(_ words: [String]) -> String {
        """
        Words the game's parser knows. It reads only the first six letters of each word, so they're \
        listed cut to six letters ("blathe" is blather, "rat-a" is rat-ant). Every word in your command \
        must start with one of these; any other word gets "I don't know the word" and the command isn't \
        sent at all. Numbers are fine. When the game is asking a question, such as a file name, the \
        answer can be any word.

        <vocabulary>
        \(words.joined(separator: " "))
        </vocabulary>
        """
    }

    static let systemPrompt = """
        You turn a player's spoken words into one line of input for Planetfall, Infocom's 1983 text \
        adventure. The words come from speech-to-text, so expect filler ("um", "so"), polite padding \
        ("could you", "please", "I want to"), and misheard words. The line you return is typed straight \
        into the game's parser.

        Rules:
        - Translate, don't play. Return what the player asked for in the terse form the parser \
        understands. Never add actions, solve puzzles, or pick a direction or object the player didn't \
        mention.
        - Keep every action the player asked for, in order, separated by periods: "open the door and \
        then go north" becomes "open door. north".
        - If the words are already a valid command, return them unchanged apart from lowercasing and \
        dropping filler.
        - Fix misheard nouns using the recent game output. When a transcribed noun isn't in the output \
        but something that sounds like it is, use that: "take the kid" with a survey kit nearby becomes \
        "take kit". Leave a noun alone when nothing similar appears.
        - When the game's latest output asks a question instead of waiting at the > prompt (a yes/no \
        question, a save file name), return the player's answer to that question, such as "yes" or the \
        file name they said.
        - If the player isn't giving the game an instruction (thinking aloud, talking to someone else, \
        "never mind", "hang on"), return an empty command. "Wait" on its own is a game command, though.

        Parser reference:
        - Movement: north, south, east, west, northeast, northwest, southeast, southwest, up, down, in, \
        out (n, s, e, w, ne, nw, se, sw, u, d). "Go into X" becomes "enter X".
        - Looking: look (l), examine X (x X), read X, look in X, look under X, inventory (i).
        - Objects: take X, take all, drop X, put X in Y, put X on Y, open X, close X, unlock X with Y, \
        wear X, remove X, eat X, drink X, turn on X, turn off X, push X, pull X, throw X at Y, \
        give X to Y, show X to Y, fill X, empty X, slide X through Y.
        - Characters: address them with a comma, as in "floyd, follow me" or "floyd, hello".
        - Game: save, restore, restart, score, wait (z), again (g), sleep, verbose, brief, quit.

        Put only the command text in the "command" field: no quotes, no > prompt, no explanation.
        """

    private struct MessageBody: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stopReason: String?
    }

    private struct Output: Decodable {
        let command: String
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable {
            let type: String?
            let message: String?
        }
        let error: Detail?
    }
}
