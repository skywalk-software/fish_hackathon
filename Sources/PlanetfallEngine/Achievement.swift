import Foundation
import Observation

/// A milestone the player can earn, detected from a sentence the game prints once at that
/// moment. Earned achievements are remembered across games and launches (see
/// `AchievementStore`), and some unlock an alternate Dock icon.
public struct Achievement: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    /// What the player did, shown in the toast and given to SNARK-9 as context.
    public var description: String
    /// Text the game prints when it's earned.
    public var trigger: String
    /// The id of the Dock icon it unlocks, if any (Art/AppIcons/<id>.png).
    public var unlocksIcon: String?

    public init(id: String, title: String, description: String, trigger: String, unlocksIcon: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.trigger = trigger
        self.unlocksIcon = unlocksIcon
    }

    public static let all: [Achievement] = [
        Achievement(id: "brig", title: "Detention, Again",
                    description: "Annoyed Ensign Blather until he threw you in the brig.",
                    trigger: "drags you to the Feinstein's brig"),
        Achievement(id: "escaped", title: "Abandon Ship",
                    description: "Escaped the exploding Feinstein, and the scrub-brush job, in an escape pod.",
                    trigger: "Through the viewport of the pod you see the Feinstein dwindle",
                    unlocksIcon: "ensign"),
        Achievement(id: "landed", title: "Planetfall",
                    description: "Survived the descent and landed on an unknown ocean planet.",
                    trigger: "The pod lands with a thud"),
    ]

    public static func with(id: String) -> Achievement? {
        all.first { $0.id == id }
    }
}

/// The achievements earned on this Mac, saved in UserDefaults so they survive restarts
/// and relaunches.
@MainActor
@Observable
public final class AchievementStore {
    /// Achievement id -> when it was first earned.
    public private(set) var earned: [String: Date]
    /// The most recent unlock this session, for showing a toast. Nil until one happens.
    public private(set) var latestUnlock: Achievement?

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "earnedAchievements"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: Self.key) as? [String: Date] ?? [:]
        earned = saved.filter { Achievement.with(id: $0.key) != nil }
    }

    public func isEarned(_ achievement: Achievement) -> Bool {
        earned[achievement.id] != nil
    }

    /// Whether the Dock icon `iconID` is available: icons no achievement unlocks always are.
    public func isUnlocked(icon iconID: String) -> Bool {
        let unlockers = Achievement.all.filter { $0.unlocksIcon == iconID }
        return unlockers.isEmpty || unlockers.contains(where: isEarned)
    }

    /// Earns every not-yet-earned achievement whose trigger appears in `text`, and returns them.
    @discardableResult
    public func record(_ text: String, at date: Date = Date()) -> [Achievement] {
        let new = Achievement.all.filter { !isEarned($0) && text.contains($0.trigger) }
        guard !new.isEmpty else { return [] }
        for achievement in new { earned[achievement.id] = date }
        latestUnlock = new.last
        save()
        return new
    }

    /// Forgets every achievement (for demos and testing).
    public func reset() {
        earned = [:]
        latestUnlock = nil
        save()
    }

    private func save() {
        defaults.set(earned, forKey: Self.key)
    }
}
