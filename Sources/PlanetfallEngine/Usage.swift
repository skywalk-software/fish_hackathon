import Foundation

/// Tokens one Claude response used, as reported in its `usage` field.
public struct TokenUsage: Equatable, Sendable, Codable {
    public var input = 0
    public var cacheRead = 0
    public var cacheWrite = 0
    public var output = 0

    public init(input: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, output: Int = 0) {
        self.input = input
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.output = output
    }

    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input + b.input, cacheRead: a.cacheRead + b.cacheRead,
                   cacheWrite: a.cacheWrite + b.cacheWrite, output: a.output + b.output)
    }

    /// Estimated cost in US dollars at Claude Opus 5.5 rates: $4 per million input tokens,
    /// $5 to write the prompt cache, $0.20 to read it, and $20 per million output tokens.
    public var estimatedCost: Double {
        (Double(input) * 4 + Double(cacheWrite) * 5 + Double(cacheRead) * 0.20 + Double(output) * 20) / 1_000_000
    }
}

/// A running total of what each Claude feature has used, kept across launches. Anthropic
/// doesn't let an API key read its own balance, so this is the app's own estimate of spend.
public final class ClaudeUsageLedger: @unchecked Sendable {
    public enum Feature: String, CaseIterable, Codable, Sendable {
        case commentary, narration, commandCleanup

        public var title: String {
            switch self {
            case .commentary: "SNARK-9 commentary"
            case .narration: "Narrator"
            case .commandCleanup: "Voice command cleanup"
            }
        }
    }

    public struct Totals: Codable, Equatable, Sendable {
        public var usage = TokenUsage()
        public var requests = 0
        public init() {}
    }

    public static let shared = ClaudeUsageLedger()

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var totals: [Feature: Totals]
    private var since: Date
    private static let key = "claudeUsageTotals"
    private static let sinceKey = "claudeUsageSince"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Feature: Totals].self, from: $0) }
        totals = saved ?? [:]
        since = defaults.object(forKey: Self.sinceKey) as? Date ?? Date()
    }

    public func record(_ feature: Feature, _ usage: TokenUsage) {
        guard usage != TokenUsage() else { return }
        lock.withLock {
            var entry = totals[feature] ?? Totals()
            entry.usage = entry.usage + usage
            entry.requests += 1
            totals[feature] = entry
            save()
        }
    }

    /// Totals per feature, and when counting started.
    public func snapshot() -> (totals: [Feature: Totals], since: Date) {
        lock.withLock { (totals, since) }
    }

    public func reset() {
        lock.withLock {
            totals = [:]
            since = Date()
            save()
        }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(totals), forKey: Self.key)
        defaults.set(since, forKey: Self.sinceKey)
    }
}

/// The Fish Audio account's API credit, read from `GET /wallet/self/api-credit`, with a history
/// of readings for estimating when it runs out.
public struct FishCredit: Equatable, Sendable, Codable {
    /// Credit left, in US dollars.
    public var balance: Double
    /// Everything ever added to the account, in US dollars.
    public var totalTopUp: Double
    public var readAt: Date

    public init(balance: Double, totalTopUp: Double, readAt: Date) {
        self.balance = balance
        self.totalTopUp = totalTopUp
        self.readAt = readAt
    }

    /// Fish speech-to-text price, US dollars per hour of audio.
    public static let speechToTextPerHour = 0.36

    public static func fetch(apiKey: String, urlSession: URLSession = .shared) async throws -> FishCredit {
        var request = URLRequest(url: URL(string: "https://api.fish.audio/wallet/self/api-credit")!, timeoutInterval: 20)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw FishTextToSpeechError.http(status: status, message: FishTextToSpeech.errorMessage(in: data)) }
        struct Body: Decodable { let credit: String; let cumulative_top_up: String? }
        let body = try JSONDecoder().decode(Body.self, from: data)
        guard let balance = Double(body.credit) else { throw FishTextToSpeechError.unreadableResponse }
        return FishCredit(balance: balance, totalTopUp: Double(body.cumulative_top_up ?? "") ?? balance, readAt: Date())
    }
}

/// Readings of the Fish balance over time, kept across launches.
public final class FishCreditHistory: @unchecked Sendable {
    public static let shared = FishCreditHistory()

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var readings: [FishCredit]
    private static let key = "fishCreditReadings"
    /// Readings older than this don't count toward the spending rate.
    private static let window: TimeInterval = 14 * 24 * 3600

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        readings = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([FishCredit].self, from: $0) } ?? []
    }

    public var latest: FishCredit? { lock.withLock { readings.last } }

    public func add(_ reading: FishCredit) {
        lock.withLock {
            // A top-up starts a fresh history, since the old readings no longer show spending.
            if let last = readings.last, reading.balance > last.balance + 0.0001 { readings = [] }
            readings.append(reading)
            readings = Array(readings.filter { reading.readAt.timeIntervalSince($0.readAt) < Self.window }.suffix(500))
            defaults.set(try? JSONEncoder().encode(readings), forKey: Self.key)
        }
    }

    /// Dollars spent per day over the readings in the window, or nil until there's at least an
    /// hour of history with some spending.
    public var dailySpend: Double? {
        lock.withLock {
            guard let first = readings.first, let last = readings.last else { return nil }
            let days = last.readAt.timeIntervalSince(first.readAt) / 86_400
            let spent = first.balance - last.balance
            guard days >= 1.0 / 24, spent > 0 else { return nil }
            return spent / days
        }
    }

    /// When the credit runs out at the current rate, or nil if that can't be estimated yet.
    public var runsOutAround: Date? {
        guard let rate = dailySpend, let last = latest else { return nil }
        return last.readAt.addingTimeInterval(last.balance / rate * 86_400)
    }
}

/// Turns a turn of game text into what the narrator reads aloud when it reads the game text
/// directly (instead of Claude's retelling): character-line markers and the title banner are
/// dropped, and anything in square brackets is removed, since Fish would take it as direction.
public enum GameTextNarration {
    public static func spokenParagraphs(from narration: String) -> [String] {
        let banner = ["Infocom interactive fiction", "Copyright (c)", "is a registered trademark",
                      "Release ", "Serial number"]
        return narration
            .components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph
                    .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { paragraph in
                !paragraph.isEmpty && paragraph != "PLANETFALL" && !banner.contains(where: paragraph.contains)
            }
    }
}
