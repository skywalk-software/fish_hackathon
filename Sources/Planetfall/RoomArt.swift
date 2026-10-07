import AppKit

/// Looks up the illustration for a room by its name from the status line.
/// "Deck Nine" -> Art/Rooms/deck-nine.jpg (or .png). Rooms without art return nil.
@MainActor
enum RoomArt {
    private static var cache: [String: NSImage] = [:]
    private static let extensions = ["jpg", "jpeg", "png", "webp"]

    static func image(for location: String) -> NSImage? {
        let slug = slug(for: location)
        if let cached = cache[slug] { return cached }
        for directory in directories {
            for ext in extensions {
                let url = directory.appendingPathComponent("\(slug).\(ext)")
                if let image = NSImage(contentsOf: url) {
                    cache[slug] = image
                    return image
                }
            }
        }
        return nil
    }

    /// "Deck Nine" -> "deck-nine", "Escape Pod" -> "escape-pod".
    static func slug(for location: String) -> String {
        location.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
    }

    /// The app bundle's Resources/Rooms (from scripts/build-app.sh), then the repo's
    /// Art/Rooms (for `swift run` and Xcode).
    private static let directories: [URL] = {
        var dirs: [URL] = []
        if let resources = Bundle.main.resourceURL {
            dirs.append(resources.appendingPathComponent("Rooms", isDirectory: true))
        }
        // This file is Sources/Planetfall/RoomArt.swift, so the repo root is three levels up.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        dirs.append(repoRoot.appendingPathComponent("Art/Rooms", isDirectory: true))
        return dirs
    }()
}
