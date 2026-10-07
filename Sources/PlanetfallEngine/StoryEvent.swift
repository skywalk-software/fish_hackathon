/// Story moments the app reacts to, detected from the game's text. Each one stays active
/// for the rest of the game (until a restart), so art can change from that point on:
/// Art/Rooms/<room>-<id>.jpg replaces a room's art once the event has happened.
public struct StoryEvent: Identifiable, Hashable, Sendable {
    public var id: String
    /// Text the game prints when the event happens.
    public var trigger: String

    public static let all: [StoryEvent] = [
        // The Feinstein starts blowing up; the escape pod opens.
        StoryEvent(id: "explosion", trigger: "A massive explosion rocks the ship"),
    ]

    /// The banner printed at the start of a game, including after an in-game restart.
    static let gameStartMarker = "Infocom interactive fiction"

    /// The events whose trigger appears in `text`, in `all` order.
    public static func triggered(by text: String) -> [StoryEvent] {
        all.filter { text.contains($0.trigger) }
    }
}
