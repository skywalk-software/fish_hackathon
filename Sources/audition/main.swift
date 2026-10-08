import Foundation
import PlanetfallEngine

// Audition Fish Audio voices for the narrator and SNARK-9 by ear.
//
//   swift run audition                                  current narrator and SNARK-9 voices
//   swift run audition compare <role> <id> [<id>...]    current voice for the role, then each id
//   swift run audition search "<words>" [--tag t] [--play]
//   swift run audition design <role> ["description"]   4 designed candidates (about $0.01)
//   swift run audition save <candidate.wav> "<title>" [--text "what the clip says"] [--visibility unlist]
//
// <role> is narrator or sidekick. Options for compare and the default run:
//   --no-tags      read the lines without [delivery] tags
//   --speed 1.1    speaking speed (default 1.0)
//   --model m      TTS model (default s2.1-pro-free; try drama-3-preview)
//   --no-play      only write the WAV files
//
// Clips go to auditions/ (gitignored). Use a voice by putting its id in .env as
// FISH_VOICE_NARRATOR or FISH_VOICE_SIDEKICK, then relaunch the app.

// MARK: - Sample lines

enum Role: String {
    case narrator, sidekick

    /// Lines each candidate reads, with Fish S2 delivery tags.
    var lines: [String] {
        switch self {
        case .sidekick: [
            "[dripping with sarcasm] Oh, splendid. Three commands in and you've polished the same bit of floor twice. The Patrol must be so proud.",
            "[theatrically weary] An exploding starship, and your first instinct is to take a nap. Truly, the stuff of legend.",
        ]
        case .narrator: [
            "[warm] You stand in a featureless corridor on Deck Nine, scrub brush in hand. A gangway leads up, and an escape pod waits behind a closed bulkhead to port.",
            "[wry] A massive explosion rocks the ship. Somewhere above, alarms begin to wail, and the escape pod door slides open.",
        ]
        }
    }

    /// What Voice Design is asked for when no description is given.
    var designBrief: String {
        switch self {
        case .sidekick:
            "A middle-aged British man, a comedic actor in the style of classic Monty Python sketches: theatrical, quick, "
                + "posh but mischievous, dripping with sarcasm and dry wit. Expressive and very human, never robotic or monotone."
        case .narrator:
            "A friendly American man in his forties narrating an adventure audiobook: warm and engaging, with a hint of wry "
                + "amusement, clear diction and a relaxed pace. Lively, not dry or flat."
        }
    }

    /// What designed candidates read (Voice Design allows at most 150 characters).
    var designSample: String {
        switch self {
        case .sidekick: "Oh, splendid. You've polished the same bit of floor twice. The Patrol must be so proud."
        case .narrator: "You stand in a featureless corridor on Deck Nine. To port, an escape pod waits behind a closed bulkhead."
        }
    }

    func currentVoice(in cast: VoiceCast) -> String {
        self == .narrator ? cast.narratorVoiceID : cast.sidekickVoiceID
    }
}

// MARK: - Fish Audio

struct Fish {
    let apiKey: String
    static let base = URL(string: "https://api.fish.audio")!

    func request(_ path: String, method: String = "GET", model: String? = nil) -> URLRequest {
        var request = URLRequest(url: Self.base.appendingPathComponent(path), timeoutInterval: 120)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let model { request.setValue(model, forHTTPHeaderField: "model") }
        return request
    }

    func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw ToolError("Fish Audio returned \(status) for \(request.url?.path ?? ""): \(detail)")
        }
        return data
    }

    func json(_ request: URLRequest) async throws -> [String: Any] {
        let data = try await send(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError("Unexpected response from \(request.url?.path ?? "")")
        }
        return object
    }

    /// A finished WAV of `text` in a voice.
    func speak(_ text: String, voiceID: String, model: String, speed: Double) async throws -> Data {
        var request = request("v1/tts", method: "POST", model: model)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["text": text, "reference_id": voiceID, "format": "wav", "latency": "normal"]
        if speed != 1 { body["prosody"] = ["speed": speed] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    /// A voice's display name, or nil if it can't be looked up.
    func title(of voiceID: String) async -> String? {
        try? await json(request("model/\(voiceID)"))["title"] as? String
    }
}

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Helpers

let outputRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("auditions")

func folder(_ name: String) throws -> URL {
    let url = outputRoot.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func slug(_ text: String) -> String {
    let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    return words.prefix(6).joined(separator: "-")
}

func play(_ file: URL) {
    let player = Process()
    player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    player.arguments = [file.path]
    try? player.run()
    player.waitUntilExit()
}

func stripTags(_ line: String) -> String {
    line.replacingOccurrences(of: #"\[[^\]]*\]\s*"#, with: "", options: .regularExpression)
}

/// Pulls `--name value` and `--flag` options out of the arguments.
struct Options {
    var positional: [String] = []
    var values: [String: String] = [:]
    var flags: Set<String> = []

    init(_ args: [String]) {
        let valued: Set<String> = ["--speed", "--model", "--tag", "--text", "--visibility"]
        var index = 0
        while index < args.count {
            let arg = args[index]
            if valued.contains(arg), index + 1 < args.count {
                values[arg] = args[index + 1]
                index += 2
            } else if arg.hasPrefix("--") {
                flags.insert(arg)
                index += 1
            } else {
                positional.append(arg)
                index += 1
            }
        }
    }
}

// MARK: - Commands

/// Reads the role's lines in each voice, one after another.
func compare(role: Role, voiceIDs: [String], fish: Fish, options: Options) async throws {
    let model = options.values["--model"] ?? "s2.1-pro-free"
    let speed = Double(options.values["--speed"] ?? "1") ?? 1
    let lines = options.flags.contains("--no-tags") ? role.lines.map(stripTags) : role.lines
    let dir = try folder("\(role.rawValue)-\(slug(model))")

    for (number, voiceID) in voiceIDs.enumerated() {
        let name = await fish.title(of: voiceID) ?? "unknown voice"
        let label = number == 0 ? "current" : "\(number)"
        print("\n[\(label)] \(name)  (\(voiceID))")
        var clips: [URL] = []
        for (lineNumber, line) in lines.enumerated() {
            let clip = dir.appendingPathComponent("\(label)-\(slug(name))-\(lineNumber + 1).wav")
            if !FileManager.default.fileExists(atPath: clip.path) || options.flags.contains("--fresh") {
                try await fish.speak(line, voiceID: voiceID, model: model, speed: speed).write(to: clip)
            }
            clips.append(clip)
        }
        if !options.flags.contains("--no-play") {
            for clip in clips { play(clip) }
        }
        print("    use it: FISH_VOICE_\(role.rawValue.uppercased())=\(voiceID)")
    }
    print("\nClips are in \(dir.path)")
}

/// Searches the public voice library.
func search(words: String, fish: Fish, options: Options) async throws {
    var components = URLComponents(url: Fish.base.appendingPathComponent("model"), resolvingAgainstBaseURL: false)!
    var query = [URLQueryItem(name: "title", value: words), URLQueryItem(name: "language", value: "en"),
                 URLQueryItem(name: "page_size", value: "15"), URLQueryItem(name: "sort_by", value: "score")]
    if let tag = options.values["--tag"] { query.append(URLQueryItem(name: "tag", value: tag)) }
    components.queryItems = query
    var request = fish.request("model")
    request.url = components.url
    let items = try await fish.json(request)["items"] as? [[String: Any]] ?? []
    if items.isEmpty { print("No voices matched \"\(words)\".") }
    let dir = try folder("search-\(slug(words))")

    for (number, item) in items.enumerated() {
        let id = item["_id"] as? String ?? "?"
        let title = item["title"] as? String ?? "?"
        let tags = (item["tags"] as? [String] ?? []).prefix(5).joined(separator: ", ")
        let description = (item["description"] as? String ?? "").replacingOccurrences(of: "\n", with: " ")
        print("\n\(number + 1). \(title)  (\(id))  likes: \(item["like_count"] as? Int ?? 0)")
        if !tags.isEmpty { print("   tags: \(tags)") }
        if !description.isEmpty { print("   \(description.prefix(140))") }

        if options.flags.contains("--play"),
           let samples = item["samples"] as? [[String: Any]], let audio = samples.first?["audio"] as? String,
           let url = URL(string: audio) {
            let clip = dir.appendingPathComponent("\(number + 1)-\(slug(title)).\(url.pathExtension.isEmpty ? "mp3" : url.pathExtension)")
            if !FileManager.default.fileExists(atPath: clip.path) {
                let (data, _) = try await URLSession.shared.data(from: url)
                try data.write(to: clip)
            }
            play(clip)
        }
    }
    print("\nCompare favorites on the game's lines: swift run audition compare sidekick <id> <id>")
}

/// Designs candidate voices from a description and plays them.
func design(role: Role, brief: String, fish: Fish, options: Options) async throws {
    var request = fish.request("v1/voice-design", method: "POST", model: "voice-design-1")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
        "instruction": brief, "reference_text": role.designSample, "language": "en", "n": 4,
    ] as [String: Any])
    print("Designing 4 \(role.rawValue) voices (about $0.01)...\n\(brief)\n")
    let candidates = try await fish.json(request)["candidates"] as? [[String: Any]] ?? []
    guard !candidates.isEmpty else { throw ToolError("Voice Design returned no candidates.") }

    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
    let dir = try folder("design-\(role.rawValue)-\(stamp)")
    try brief.write(to: dir.appendingPathComponent("brief.txt"), atomically: true, encoding: .utf8)
    for (number, candidate) in candidates.enumerated() {
        guard let base64 = candidate["audio_base64"] as? String, let audio = Data(base64Encoded: base64) else { continue }
        let clip = dir.appendingPathComponent("candidate-\(number + 1).wav")
        try audio.write(to: clip)
        // What the clip says, for `save`.
        try (candidate["text"] as? String ?? role.designSample)
            .write(to: clip.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        print("Candidate \(number + 1): \(clip.path)")
        if !options.flags.contains("--no-play") { play(clip) }
    }
    print("\nKeep one: swift run audition save \"\(dir.path)/candidate-N.wav\" \"SNARK-9 (British)\"")
}

/// Turns a clip (e.g. a designed candidate) into a reusable private voice.
func save(clip: URL, title: String, fish: Fish, options: Options) async throws {
    let audio = try Data(contentsOf: clip)
    let sidecar = clip.deletingPathExtension().appendingPathExtension("txt")
    let text = options.values["--text"] ?? (try? String(contentsOf: sidecar, encoding: .utf8))

    let boundary = "audition-\(UUID().uuidString)"
    var body = Data()
    func field(_ name: String, _ value: String) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }
    field("type", "tts")
    field("title", title)
    field("train_mode", "fast")
    // "private" voices only work with this account's key; "unlist" lets any key use the id.
    field("visibility", options.values["--visibility"] ?? "private")
    if let text { field("texts", text) }
    body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"voices\"; filename=\"\(clip.lastPathComponent)\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
    body.append(audio)
    body.append(Data("\r\n--\(boundary)--\r\n".utf8))

    var request = fish.request("model", method: "POST")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    let model = try await fish.json(request)
    guard let id = model["_id"] as? String else { throw ToolError("Fish Audio didn't return a voice id.") }
    print("Saved \"\(title)\" (\(options.values["--visibility"] ?? "private")): \(id)")
    print("Hear it on the game's lines: swift run audition compare <narrator|sidekick> \(id)")
    print("Use it: add FISH_VOICE_NARRATOR=\(id) or FISH_VOICE_SIDEKICK=\(id) to .env and relaunch the app.")
}

// MARK: - Main

let options = Options(Array(CommandLine.arguments.dropFirst()))
guard let apiKey = FishAPIKey.load() else {
    print("No FISH_API_KEY in the environment or .env.")
    exit(1)
}
let fish = Fish(apiKey: apiKey)
let cast = VoiceCast.load()
let args = options.positional

do {
    switch args.first {
    case nil:
        try await compare(role: .narrator, voiceIDs: [cast.narratorVoiceID], fish: fish, options: options)
        try await compare(role: .sidekick, voiceIDs: [cast.sidekickVoiceID], fish: fish, options: options)
    case "compare":
        guard args.count >= 2, let role = Role(rawValue: args[1]) else { throw ToolError("Usage: audition compare <narrator|sidekick> <id>...") }
        try await compare(role: role, voiceIDs: [role.currentVoice(in: cast)] + args.dropFirst(2), fish: fish, options: options)
    case "search":
        guard args.count >= 2 else { throw ToolError("Usage: audition search \"<words>\" [--tag t] [--play]") }
        try await search(words: args.dropFirst().joined(separator: " "), fish: fish, options: options)
    case "design":
        guard args.count >= 2, let role = Role(rawValue: args[1]) else { throw ToolError("Usage: audition design <narrator|sidekick> [\"description\"]") }
        let brief = args.count >= 3 ? args.dropFirst(2).joined(separator: " ") : role.designBrief
        try await design(role: role, brief: brief, fish: fish, options: options)
    case "save":
        guard args.count >= 3 else { throw ToolError("Usage: audition save <candidate.wav> \"<title>\" [--text \"...\"]") }
        try await save(clip: URL(fileURLWithPath: args[1]), title: args.dropFirst(2).joined(separator: " "), fish: fish, options: options)
    default:
        throw ToolError("Unknown command \"\(args[0])\". Commands: compare, search, design, save (or none for the current voices).")
    }
} catch {
    print("Error: \(error)")
    exit(1)
}
