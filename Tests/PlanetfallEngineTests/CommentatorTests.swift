import Foundation
import Testing
@testable import PlanetfallEngine

/// Serves a canned response to every request, so the streaming path runs without the network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var body = Data()

    static func session(statusCode: Int, body: String) -> URLSession {
        Self.statusCode = statusCode
        Self.body = Data(body.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil,
                                       headerFields: ["content-type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

// Serialized: the stub's canned response is shared.
@Suite(.serialized)
struct CommentatorTests {
    private let context = CommentaryContext(
        location: "Deck Nine", score: 0, moves: 4454,
        recentOutput: "Deck Nine\nA corridor.\n> scrub floor\nYou scrub the floor. It is now slightly less filthy.",
        previousLines: ["Riveting stuff, Ensign."])

    private func body(of request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Server-sent events for a reply made of `deltas`, with a thinking block first.
    private func sse(_ deltas: [String], stopReason: String = "end_turn") -> String {
        var lines = [
            #"event: message_start"#,
            #"data: {"type":"message_start","message":{"id":"msg_1","type":"message"}}"#, "",
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#, "",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}"#, "",
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#, "",
        ]
        for delta in deltas {
            let escaped = String(data: try! JSONSerialization.data(withJSONObject: [delta], options: [.fragmentsAllowed]), encoding: .utf8)!
                .dropFirst().dropLast()
            lines += [#"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"# + escaped + #"}}"#, ""]
        }
        lines += [
            #"data: {"type":"message_delta","delta":{"stop_reason":""# + stopReason + #""},"usage":{"output_tokens":12}}"#, "",
            #"data: {"type":"message_stop"}"#, "",
        ]
        return lines.joined(separator: "\n")
    }

    private func collect(_ commentator: Commentator) async throws -> [String] {
        var deltas: [String] = []
        for try await delta in commentator.commentary(on: context) { deltas.append(delta) }
        return deltas
    }

    @Test func buildsAStreamingRequestWithCachedPersonaAndFallbacks() throws {
        let request = try Commentator(apiKey: "sk-test").makeRequest(context: context)
        #expect(request.url == Commentator.endpoint)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")

        let body = try body(of: request)
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["stream"] as? Bool == true)
        #expect(body["fallbacks"] as? String == "default")
        #expect((body["output_config"] as? [String: Any])?["effort"] as? String == "low")
        // Opus 5.5 rejects disabled thinking, so the request never sends a thinking setting.
        #expect(body["thinking"] == nil)

        let system = try #require((body["system"] as? [[String: Any]])?.first)
        #expect((system["cache_control"] as? [String: String])?["type"] == "ephemeral")
        #expect((system["text"] as? String)?.contains("SNARK-9") == true)

        let message = try #require((body["messages"] as? [[String: Any]])?.first)
        let content = try #require(message["content"] as? String)
        #expect(content.contains("Room: Deck Nine | Score: 0 | Moves: 4454"))
        #expect(content.contains("> scrub floor"))
        #expect(content.contains("- Riveting stuff, Ensign."))
    }

    @Test func streamsTextDeltasAndSkipsThinking() async throws {
        let session = StubURLProtocol.session(statusCode: 200, body: sse(["Bold move, ", "scrubbing the ", "floor you already scrubbed."]))
        let deltas = try await collect(Commentator(apiKey: "sk-test", urlSession: session))
        #expect(deltas.joined() == "Bold move, scrubbing the floor you already scrubbed.")
    }

    @Test func passingOnATurnYieldsNothing() async throws {
        let session = StubURLProtocol.session(statusCode: 200, body: sse(["PA", "SS"]))
        #expect(try await collect(Commentator(apiKey: "sk-test", urlSession: session)).isEmpty)
    }

    @Test func refusalThrows() async throws {
        let session = StubURLProtocol.session(statusCode: 200, body: sse([], stopReason: "refusal"))
        await #expect(throws: CommandInterpreterError.self) {
            _ = try await collect(Commentator(apiKey: "sk-test", urlSession: session))
        }
    }

    @Test func surfacesHTTPErrors() async throws {
        let session = StubURLProtocol.session(
            statusCode: 401, body: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)
        do {
            _ = try await collect(Commentator(apiKey: "bad", urlSession: session))
            Issue.record("expected an error")
        } catch let error as CommandInterpreterError {
            guard case .http(401, "authentication_error", "invalid x-api-key") = error else {
                Issue.record("unexpected error \(error)")
                return
            }
        }
    }

    @Test func passFilterOnlyHoldsBackWhatCouldBeThePassToken() {
        var filter = Commentator.PassFilter()
        #expect(filter.feed("P") == nil)
        #expect(filter.feed("assive aggressive much?") == "Passive aggressive much?")
        #expect(filter.feed(" Yes.") == " Yes.")

        var pass = Commentator.PassFilter()
        #expect(pass.feed("PASS") == nil)
        #expect(pass.finish() == nil)

        var short = Commentator.PassFilter()
        #expect(short.feed("P") == nil)
        #expect(short.finish() == "P")
    }

    /// Calls the real API. Opt in: ANTHROPIC_LIVE_TESTS=1 swift test --filter commentsOnARealTurn
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_LIVE_TESTS"] == "1" && AnthropicAPIKey.load() != nil))
    func commentsOnARealTurn() async throws {
        let commentator = Commentator(apiKey: try #require(AnthropicAPIKey.load()))
        let quip = try await collect(commentator).joined()
        print("SNARK-9:", quip.isEmpty ? "(passed)" : quip)
        #expect(quip.count < 400)
    }
}
