import Foundation

/// Finds dfrotz, the story file, and the saves folder.
public enum GameLocator {
    /// `DFROTZ_PATH`, then the Homebrew locations (an app launched from Finder doesn't get the shell's PATH).
    public static func dfrotzURL() -> URL? {
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment["DFROTZ_PATH"] { candidates.append(override) }
        candidates += ["/opt/homebrew/bin/dfrotz", "/usr/local/bin/dfrotz"]
        return firstExisting(candidates, executable: true)
    }

    /// `PLANETFALL_STORY`, then the app bundle's Resources (from scripts/build-app.sh),
    /// then the repo's Story folder (for `swift run` and Xcode).
    public static func storyURL() -> URL? {
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment["PLANETFALL_STORY"] { candidates.append(override) }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("planetfall.z3").path)
        }
        candidates.append(repoRoot.appendingPathComponent("Story/planetfall.z3").path)
        return firstExisting(candidates, executable: false)
    }

    /// The source checkout, for `swift run` and Xcode builds.
    /// This file is Sources/PlanetfallEngine/GameLocator.swift, so the repo root is three levels up.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// ~/Library/Application Support/Planetfall/Saves
    public static func savesDirectory() -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("Planetfall/Saves", isDirectory: true)
    }

    private static func firstExisting(_ paths: [String], executable: Bool) -> URL? {
        let fm = FileManager.default
        let path = paths.first { executable ? fm.isExecutableFile(atPath: $0) : fm.isReadableFile(atPath: $0) }
        return path.map { URL(fileURLWithPath: $0) }
    }
}
