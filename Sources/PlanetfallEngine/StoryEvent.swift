/// Story moments the app reacts to, detected from the game's text. Once triggered, an
/// event stays active until its `endedBy` text appears (or the game restarts), so art can
/// change from that point on: Art/Rooms/<room>-<id>.jpg replaces a room's art while the
/// event is active. See `GameSession.artTags` for how events combine.
public struct StoryEvent: Identifiable, Hashable, Sendable {
    public var id: String
    /// Text the game prints when the event happens.
    public var trigger: String
    /// Text the game prints when the event is over, if it ever is.
    public var endedBy: String?

    public static let all: [StoryEvent] = [
        // The Feinstein starts blowing up and the escape pod opens; it's over once the
        // pod has launched and the ship is behind you.
        StoryEvent(id: "explosion", trigger: "A massive explosion rocks the ship",
                   endedBy: "Through the viewport of the pod you see the Feinstein dwindle"),
        // After the launch, the planet comes into view through the pod's viewport; it's in
        // view (or, briefly, behind a polarized viewport) until the pod touches down.
        StoryEvent(id: "planet", trigger: "a nearby planet swings into view through the port",
                   endedBy: "The pod lands with a thud"),
    ]

    /// Art tags for being inside an object, keyed by the object's name in dfrotz's
    /// object trace: in the safety web, rooms use their "-webbing" art.
    public static let holderTags: [String: String] = [
        "safety web": "webbing",
    ]

    /// The banner printed at the start of a game, including after an in-game restart.
    static let gameStartMarker = "Infocom interactive fiction"

    /// The events whose trigger appears in `text`, in `all` order (e.g. to play a sound the
    /// moment one happens).
    static func triggered(by text: String) -> [StoryEvent] {
        all.filter { text.contains($0.trigger) }
    }

    /// Applies one turn's text to the active event ids, keeping them in the order they began.
    static func update(_ active: inout [String], with text: String) {
        for event in all {
            if let end = event.endedBy, text.contains(end) {
                active.removeAll { $0 == event.id }
            } else if text.contains(event.trigger), !active.contains(event.id) {
                active.append(event.id)
            }
        }
    }

    /// Non-empty subsets of `tags`, each in the original order, to try as art names. Larger
    /// subsets come first; among equal sizes, ones containing newer tags come first.
    /// [explosion, webbing] -> [explosion, webbing], [webbing], [explosion].
    public static func tagCombinations(_ tags: [String]) -> [[String]] {
        let count = tags.count
        guard count > 0 else { return [] }
        let masks = (1..<(1 << count)).sorted { a, b in
            if a.nonzeroBitCount != b.nonzeroBitCount { return a.nonzeroBitCount > b.nonzeroBitCount }
            return a > b  // higher bits are newer tags
        }
        return masks.map { mask in tags.indices.filter { mask & (1 << $0) != 0 }.map { tags[$0] } }
    }
}
