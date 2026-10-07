import Foundation
import Testing
@testable import PlanetfallEngine

struct DotEnvTests {
    @Test func parsesKeysCommentsQuotesAndExport() {
        let values = DotEnv.parse("""
            # Fish Audio API key
            FISH_API_KEY = abc123
            export OTHER="quoted value"
            SINGLE='x y'
            INLINE=plain # trailing comment
            EMPTY=
            not a pair
            """)
        #expect(values["FISH_API_KEY"] == "abc123")
        #expect(values["OTHER"] == "quoted value")
        #expect(values["SINGLE"] == "x y")
        #expect(values["INLINE"] == "plain")
        #expect(values["EMPTY"] == "")
        #expect(values.count == 5)
    }
}

struct FishAPIKeyTests {
    private func envFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fish-env-\(UUID().uuidString)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func environmentWinsOverEnvFile() throws {
        let file = try envFile("FISH_API_KEY=from-file\n")
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(FishAPIKey.load(environment: ["FISH_API_KEY": "from-env"], envFile: file) == "from-env")
    }

    @Test func fallsBackToEnvFileWhenEnvironmentIsEmpty() throws {
        let file = try envFile("# comment\nFISH_API_KEY=from-file\n")
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(FishAPIKey.load(environment: ["FISH_API_KEY": "  "], envFile: file) == "from-file")
    }

    @Test func keysLiveInTheRepoFromSourceAndInApplicationSupportWhenInstalled() throws {
        #expect(FishAPIKey.envFileURL == GameLocator.repoRoot.appendingPathComponent(".env"))
        // A Homebrew build's source folder is deleted after install.
        let installed = FishAPIKey.envFileURL(repoRoot: URL(fileURLWithPath: "/nonexistent/build-dir"))
        #expect(installed.path.hasSuffix("Library/Application Support/Planetfall/.env"))
    }

    @Test func blankOrMissingKeyIsNil() throws {
        let file = try envFile("FISH_API_KEY=\n")
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(FishAPIKey.load(environment: [:], envFile: file) == nil)
        #expect(FishAPIKey.load(environment: [:], envFile: file.appendingPathExtension("missing")) == nil)
    }
}

struct WAVTests {
    @Test func writesA44ByteHeaderThenLittleEndianSamples() {
        let data = WAV.encode(samples: [0, 1, -1, .max], sampleRate: 48_000)
        let bytes = [UInt8](data)
        func u32(_ offset: Int) -> UInt32 { bytes[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) } }
        func u16(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8 }

        #expect(data.count == 44 + 8)
        #expect(String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF")
        #expect(u32(4) == 36 + 8)
        #expect(String(decoding: bytes[8..<16], as: UTF8.self) == "WAVEfmt ")
        #expect(u16(20) == 1)        // PCM
        #expect(u16(22) == 1)        // mono
        #expect(u32(24) == 48_000)
        #expect(u32(28) == 96_000)
        #expect(u16(34) == 16)
        #expect(String(decoding: bytes[36..<40], as: UTF8.self) == "data")
        #expect(u32(40) == 8)
        #expect(Array(bytes[44...]) == [0x00, 0x00, 0x01, 0x00, 0xFF, 0xFF, 0xFF, 0x7F])
    }
}

struct FishSpeechToTextTests {
    @Test(arguments: [
        ("<|speaker:0|> Open the pod.", "Open the pod"),
        ("<|speaker:0|> [laughter] take   the brush, then go north! ", "take the brush, then go north"),
        ("What is Floyd doing?", "What is Floyd doing"),
        ("<|speaker:0|>", ""),
        ("", ""),
    ])
    func cleansTranscriptForTheParser(raw: String, expected: String) {
        #expect(FishSpeechToText.cleanTranscript(raw) == expected)
    }

    @Test func buildsMultipartRequestWithModelHeader() throws {
        let stt = FishSpeechToText(apiKey: "test-key")
        let request = stt.makeRequest(audio: Data("RIFFxxxx".utf8), boundary: "B")
        #expect(request.url == FishSpeechToText.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "model") == "transcribe-1-pro")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=B")

        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("name=\"ignore_timestamps\"\r\n\r\ntrue\r\n"))
        #expect(body.contains("name=\"language\"\r\n\r\nen\r\n"))
        #expect(body.contains("name=\"tag_audio_events\"\r\n\r\nfalse\r\n"))
        #expect(body.contains("name=\"audio\"; filename=\"command.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFFxxxx\r\n"))
        #expect(body.hasSuffix("--B--\r\n"))
    }

    @Test func omitsProOnlyFieldsForTranscribe1() throws {
        let request = FishSpeechToText(apiKey: "k", model: "transcribe-1", language: nil)
            .makeRequest(audio: Data(), boundary: "B")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(!body.contains("tag_audio_events"))
        #expect(!body.contains("name=\"language\""))
    }

    @Test func decodesSuccessAndErrors() throws {
        let ok = Data(#"{"text":"<|speaker:0|> Look around.","duration":1.2,"segments":[]}"#.utf8)
        #expect(try FishSpeechToText.decode(ok, statusCode: 200) == "Look around")

        let unauthorized = Data(#"{"status":401,"message":"Invalid API key"}"#.utf8)
        #expect {
            try FishSpeechToText.decode(unauthorized, statusCode: 401)
        } throws: { error in
            guard case .http(401, "Invalid API key") = error as? FishSpeechToTextError else { return false }
            return true
        }
        #expect(throws: FishSpeechToTextError.self) { try FishSpeechToText.decode(Data("<html>".utf8), statusCode: 502) }
        #expect(throws: FishSpeechToTextError.self) { try FishSpeechToText.decode(Data("nope".utf8), statusCode: 200) }
    }

    /// Calls the real API with speech from macOS `say`. Opt in: FISH_LIVE_TESTS=1 swift test
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FISH_LIVE_TESTS"] == "1" && FishAPIKey.load() != nil))
    func transcribesRealSpeech() async throws {
        let wavURL = FileManager.default.temporaryDirectory.appendingPathComponent("fish-live-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", wavURL.path, "--file-format=WAVE", "--data-format=LEI16@16000", "Open the pod and take the kit."]
        try say.run()
        say.waitUntilExit()

        let stt = FishSpeechToText(apiKey: try #require(FishAPIKey.load()))
        let text = try await stt.transcribe(wav: try Data(contentsOf: wavURL))
        #expect(text.lowercased().contains("pod"))
        #expect(!text.contains("<|"))
    }
}
