/// The game's non-player characters, keyed by the short names the game uses for their
/// objects (what dfrotz's `-o` trace prints). `id` is used for art and voices:
/// Art/NPCs/<id>.jpg.
public struct GameCharacter: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var objectName: String

    public static let all: [GameCharacter] = [
        GameCharacter(id: "blather", name: "Ensign Blather", objectName: "Ensign First Class"),
        GameCharacter(id: "ambassador", name: "Alien Ambassador", objectName: "alien ambassador"),
        GameCharacter(id: "floyd", name: "Floyd", objectName: "multiple purpose robot"),
        GameCharacter(id: "rat-ant", name: "Rat-Ant", objectName: "rat-like, ant-like man-sized monster"),
        GameCharacter(id: "troll", name: "Hairy Biped", objectName: "hairy growling biped"),
        GameCharacter(id: "grue", name: "Grue", objectName: "lurking fanged creature"),
        GameCharacter(id: "microbe", name: "Microbe", objectName: "microbe"),
    ]

    /// Applies one object event to `locations` (character id -> room name; characters
    /// removed from play have no entry). Events for other objects are ignored.
    static func apply(_ event: ObjectEvent, to locations: inout [String: String]) {
        switch event {
        case .moved(let args):
            for character in all where args.hasPrefix(character.objectName + " ") {
                locations[character.id] = String(args.dropFirst(character.objectName.count + 1))
            }
        case .removed(let object):
            for character in all where object == character.objectName {
                locations[character.id] = nil
            }
        }
    }
}
