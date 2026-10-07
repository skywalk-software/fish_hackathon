import AppKit

/// Loads illustrations from the Art folders by name.
/// Rooms: "Deck Nine" -> Art/Rooms/deck-nine.jpg. Characters: Art/NPCs/<character id>.jpg.
/// Anything without art returns nil.
@MainActor
enum Artwork {
    enum Kind: String {
        case room = "Rooms"
        case character = "NPCs"
    }

    private static var cache: [String: NSImage] = [:]
    private static let extensions = ["jpg", "jpeg", "png", "webp"]

    static func room(_ location: String) -> NSImage? {
        image(.room, slug: slug(for: location))
    }

    static func character(_ id: String) -> NSImage? {
        image(.character, slug: id)
    }

    /// Art/AppIcon.png, used for the Dock icon when running without a bundle icon (`swift run`, Xcode).
    static func appIcon() -> NSImage? {
        roots.lazy.compactMap { NSImage(contentsOf: $0.appendingPathComponent("AppIcon.png")) }.first
    }

    /// "Deck Nine" -> "deck-nine", "Escape Pod" -> "escape-pod".
    static func slug(for name: String) -> String {
        name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
    }

    private static func image(_ kind: Kind, slug: String) -> NSImage? {
        let key = "\(kind.rawValue)/\(slug)"
        if let cached = cache[key] { return cached }
        for root in roots {
            for ext in extensions {
                let url = root.appendingPathComponent("\(key).\(ext)")
                if let image = NSImage(contentsOf: url) {
                    cache[key] = image
                    return image
                }
            }
        }
        return nil
    }

    /// The app bundle's Resources/Art (from scripts/build-app.sh), then the repo's
    /// Art folder (for `swift run` and Xcode).
    private static let roots: [URL] = {
        var dirs: [URL] = []
        if let resources = Bundle.main.resourceURL {
            dirs.append(resources.appendingPathComponent("Art", isDirectory: true))
        }
        // This file is Sources/Planetfall/Artwork.swift, so the repo root is three levels up.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        dirs.append(repoRoot.appendingPathComponent("Art", isDirectory: true))
        return dirs
    }()
}
