import Foundation

/// Finds the Fish Audio API key: `FISH_API_KEY` in the environment, then the repo's `.env` file.
public enum FishAPIKey {
    /// The repo-root `.env` (gitignored), with a line like `FISH_API_KEY=...`.
    public static var envFileURL: URL {
        GameLocator.repoRoot.appendingPathComponent(".env")
    }

    public static func load() -> String? {
        load(environment: ProcessInfo.processInfo.environment, envFile: envFileURL)
    }

    static func load(environment: [String: String], envFile: URL) -> String? {
        if let key = nonEmpty(environment["FISH_API_KEY"]) { return key }
        guard let contents = try? String(contentsOf: envFile, encoding: .utf8) else { return nil }
        return nonEmpty(DotEnv.parse(contents)["FISH_API_KEY"])
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }
}

/// Minimal `.env` parser: `KEY=value` lines, `#` comments, an optional `export ` prefix, and
/// optional single or double quotes around the value.
enum DotEnv {
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
