import Foundation
import Testing
@testable import PlanetfallEngine

struct AnthropicAPIKeyTests {
    @Test func readsAnthropicKeyFromEnvironmentThenEnvFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("anthropic-env-\(UUID().uuidString)")
        try "FISH_API_KEY=fish\nANTHROPIC_API_KEY=from-file\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(AnthropicAPIKey.load(environment: ["ANTHROPIC_API_KEY": "from-env"], envFile: file) == "from-env")
        #expect(AnthropicAPIKey.load(environment: [:], envFile: file) == "from-file")
        #expect(FishAPIKey.load(environment: [:], envFile: file) == "fish")
    }
}

struct CommandContextTests {
    @Test func keepsTheNewestEntriesThatFit() {
        let entries: [TranscriptEntry] = [
            .narration(id: 0, text: String(repeating: "x", count: 50)),
            .command(id: 1, text: "look"),
            .narration(id: 2, text: "Deck Nine. A survey kit lies here."),
        ]
        let context = CommandContext.recent(entries, location: "Deck Nine", maxCharacters: 60)
        #expect(context.location == "Deck Nine")
        #expect(context.recentOutput == "> look\nDeck Nine. A survey kit lies here.")
    }

    @Test func clipsASingleOversizedEntryToItsEnd() {
        let context = CommandContext.recent([.narration(id: 0, text: "abcdefghij")], location: nil, maxCharacters: 4)
        #expect(context.recentOutput == "ghij")
    }
}

struct CommandInterpreterTests {
    private let context = CommandContext(location: "Deck Nine", recentOutput: "> look\nA survey kit lies here.")

    private func body(of request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func buildsAMessagesRequestWithCachedSystemPromptAndJSONSchema() throws {
        let request = try CommandInterpreter(apiKey: "test-key").makeRequest(heard: "um pick up the kid", context: context)
        #expect(request.url == CommandInterpreter.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")

        let body = try body(of: request)
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["fallbacks"] as? String == "default")
        #expect(body["thinking"] == nil)

        let system = try #require(body["system"] as? [[String: Any]])
        #expect(system.count == 1)
        #expect(system[0]["text"] as? String == CommandInterpreter.systemPrompt)
        #expect((system[0]["cache_control"] as? [String: String]) == ["type": "ephemeral"])

        let messages = try #require(body["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? String)
        #expect(messages.count == 1 && messages[0]["role"] as? String == "user")
        #expect(content.contains("Current room: Deck Nine"))
        #expect(content.contains("<game_output>\n> look\nA survey kit lies here.\n</game_output>"))
        #expect(content.hasSuffix("The player said: um pick up the kid"))

        let outputConfig = try #require(body["output_config"] as? [String: Any])
        #expect(outputConfig["effort"] as? String == "low")
        let format = try #require(outputConfig["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["schema"] as? [String: Any])
        #expect(schema["required"] as? [String] == ["command"])
        #expect(schema["additionalProperties"] as? Bool == false)
    }

    @Test func omitsEffortAndFallbacksWhenTurnedOff() throws {
        let request = try CommandInterpreter(apiKey: "k", model: "claude-haiku-4-5", effort: nil, serverSideFallbacks: false)
            .makeRequest(heard: "north", context: context)
        let body = try body(of: request)
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        #expect(body["fallbacks"] == nil)
        #expect(body["model"] as? String == "claude-haiku-4-5")
        let outputConfig = try #require(body["output_config"] as? [String: Any])
        #expect(outputConfig["effort"] == nil)
        #expect(outputConfig["format"] != nil)
    }

    private func response(stopReason: String, text: String?) -> Data {
        var content: [[String: Any]] = [["type": "thinking", "thinking": "", "signature": "sig"]]
        if let text { content.append(["type": "text", "text": text]) }
        let body: [String: Any] = ["type": "message", "role": "assistant", "content": content, "stop_reason": stopReason]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    @Test func readsTheCommandFromTheTextBlockAfterThinking() throws {
        let data = response(stopReason: "end_turn", text: #"{"command": " take kit.\nnorth "}"#)
        #expect(try CommandInterpreter.decode(data, statusCode: 200) == "take kit. north")
    }

    @Test func emptyCommandMeansNotACommand() throws {
        let data = response(stopReason: "end_turn", text: #"{"command": ""}"#)
        #expect(try CommandInterpreter.decode(data, statusCode: 200) == "")
    }

    @Test func refusalAndCutOffRepliesThrow() {
        #expect {
            try CommandInterpreter.decode(response(stopReason: "refusal", text: nil), statusCode: 200)
        } throws: { error in
            guard case .refused = error as? CommandInterpreterError else { return false }
            return true
        }
        #expect {
            try CommandInterpreter.decode(response(stopReason: "max_tokens", text: #"{"comm"#), statusCode: 200)
        } throws: { error in
            guard case .incomplete("max_tokens") = error as? CommandInterpreterError else { return false }
            return true
        }
    }

    @Test func surfacesAPIErrors() {
        let unauthorized = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"},"request_id":"req_1"}"#.utf8)
        #expect {
            try CommandInterpreter.decode(unauthorized, statusCode: 401)
        } throws: { error in
            guard case .http(401, "authentication_error", "invalid x-api-key") = error as? CommandInterpreterError else { return false }
            return true
        }
        #expect(throws: CommandInterpreterError.self) { try CommandInterpreter.decode(Data("<html>".utf8), statusCode: 529) }
        #expect(throws: CommandInterpreterError.self) { try CommandInterpreter.decode(Data("nope".utf8), statusCode: 200) }
        #expect(throws: CommandInterpreterError.self) {
            try CommandInterpreter.decode(response(stopReason: "end_turn", text: "take kit"), statusCode: 200)
        }
    }

    /// Calls the real API. Opt in: ANTHROPIC_LIVE_TESTS=1 swift test --filter interpretsRealSpeech
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_LIVE_TESTS"] == "1" && AnthropicAPIKey.load() != nil))
    func interpretsRealSpeech() async throws {
        let interpreter = CommandInterpreter(apiKey: try #require(AnthropicAPIKey.load()))
        let context = CommandContext(location: "Deck Nine", recentOutput: """
            Deck Nine
            This is a featureless corridor similar to every other corridor on the ship. It curves away to \
            starboard, and a gangway leads up. To port is the entrance to one of the ship's primary escape pods. \
            The pod bulkhead is closed.
            A survey kit is lying here.
            """)
        let command = try await interpreter.interpret("um could you please pick up the kid", context: context)
        #expect(command.lowercased().contains("kit"))
        #expect(try await interpreter.interpret("hmm let me think about this", context: context) == "")
    }
}
