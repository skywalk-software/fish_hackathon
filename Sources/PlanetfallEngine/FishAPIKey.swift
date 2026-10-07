import Foundation

/// Finds the Fish Audio API key: `FISH_API_KEY` in the environment, then the `.env` file at `envFileURL`.
public enum FishAPIKey {
    /// Where the keys live, as lines like `FISH_API_KEY=...`: the repo's gitignored `.env` when
    /// running from a source checkout, otherwise ~/Library/Application Support/Planetfall/.env
    /// (an install, e.g. from Homebrew, has no source folder).
    public static var envFileURL: URL {
        envFileURL(repoRoot: GameLocator.repoRoot)
    }

    static func envFileURL(repoRoot: URL) -> URL {
        if FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("Package.swift").path) {
            return repoRoot.appendingPathComponent(".env")
        }
        return URL.applicationSupportDirectory.appendingPathComponent("Planetfall/.env")
    }

    public static func load() -> String? {
        load(environment: ProcessInfo.processInfo.environment, envFile: envFileURL)
    }

    static func load(environment: [String: String], envFile: URL) -> String? {
        DotEnv.value(for: "FISH_API_KEY", environment: environment, envFile: envFile)
    }
}

/// Finds the Anthropic API key used to clean up voice commands with Claude: `ANTHROPIC_API_KEY`
/// in the environment, then the same `.env` file.
public enum AnthropicAPIKey {
    public static func load() -> String? {
        load(environment: ProcessInfo.processInfo.environment, envFile: FishAPIKey.envFileURL)
    }

    static func load(environment: [String: String], envFile: URL) -> String? {
        DotEnv.value(for: "ANTHROPIC_API_KEY", environment: environment, envFile: envFile)
    }
}

/// Minimal `.env` parser: `KEY=value` lines, `#` comments, an optional `export ` prefix, and
/// optional single or double quotes around the value.
enum DotEnv {
    /// `name` from the environment if it's set and non-blank, otherwise from `envFile`.
    static func value(for name: String, environment: [String: String], envFile: URL) -> String? {
        if let value = nonEmpty(environment[name]) { return value }
        guard let contents = try? String(contentsOf: envFile, encoding: .utf8) else { return nil }
        return nonEmpty(parse(contents)[name])
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }

    static func parse(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'", value.count >= 2, value.last == quote {
                value = String(value.dropFirst().dropLast())
            } else if let comment = value.range(of: " #") {
                value = value[..<comment.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            values[key] = value
        }
        return values
    }
}
