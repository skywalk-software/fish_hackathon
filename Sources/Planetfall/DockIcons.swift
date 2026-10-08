import AppKit
import Observation
import PlanetfallEngine

/// An icon the player can pick for the Dock. Art is Art/AppIcons/<id>.png (already shaped
/// with scripts/make-icon.swift). Icons an achievement unlocks stay locked until it's earned.
struct DockIcon: Identifiable, Hashable {
    var id: String
    var name: String

    static let all: [DockIcon] = [
        DockIcon(id: "poster", name: "Recruitment Poster"),
        DockIcon(id: "ensign", name: "Ensign Seventh Class"),
    ]
    static let defaultID = "poster"

    /// The achievement that unlocks this icon, if any.
    var unlockedBy: Achievement? {
        Achievement.all.first { $0.unlocksIcon == id }
    }
}

/// The Dock icon choice. Only the Dock changes: the Finder icon stays the bundle's icon,
/// because swapping that would break the app's code signature.
@MainActor
@Observable
final class DockIconSettings {
    /// The chosen icon's id, remembered between launches.
    private(set) var selectedID: String

    @ObservationIgnored private let achievements: AchievementStore
    private static let key = "dockIcon"

    init(achievements: AchievementStore) {
        self.achievements = achievements
        selectedID = UserDefaults.standard.string(forKey: Self.key) ?? DockIcon.defaultID
    }

    func isUnlocked(_ icon: DockIcon) -> Bool {
        achievements.isUnlocked(icon: icon.id)
    }

    /// The icon in use: the chosen one, or the default if it's locked (e.g. after
    /// achievements were reset) or missing.
    var current: DockIcon {
        DockIcon.all.first { $0.id == selectedID && isUnlocked($0) }
            ?? DockIcon.all.first { $0.id == DockIcon.defaultID }!
    }

    func select(_ icon: DockIcon) {
        guard isUnlocked(icon) else { return }
        selectedID = icon.id
        UserDefaults.standard.set(icon.id, forKey: Self.key)
        apply()
    }

    /// Puts the current icon in the Dock. Call at launch and after achievements change.
    func apply() {
        NSApp.applicationIconImage = Artwork.dockIcon(current.id) ?? Artwork.appIcon()
    }
}
