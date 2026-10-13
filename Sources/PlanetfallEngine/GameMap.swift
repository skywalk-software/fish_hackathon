import Foundation

/// The full map (Art/Map/planetfall-map.json, written by scripts/map/draw.py): where each room
/// sits on the map page, its name as the game prints it, and which rooms connect.
///
/// Room ids are the game's own (DECK-NINE, PHYSICAL-PLANT-TWO). A room drawn twice gets a
/// suffix on its second drawing: the elevators appear at both ends of their shafts
/// (UPPER-ELEVATOR at the lobby, UPPER-ELEVATOR@top at the tower).
public struct GameMap: Decodable, Sendable {
    public struct Room: Decodable, Sendable, Equatable {
        /// The room's name as the game prints it ("Physical Plant").
        public var name: String
        /// The room's box on the page, as fractions of the page's width and height, from the top left.
        public var x: Double
        public var y: Double
        public var w: Double
        public var h: Double

        public init(name: String, x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0) {
            self.name = name
            self.x = x
            self.y = y
            self.w = w
            self.h = h
        }
    }

    /// The "you are here" marker: its center sits `inset` pixels in from the lower-right corner
    /// of the room's box, with this `radius`.
    public struct Marker: Decodable, Sendable, Equatable {
        public var inset: Double = 11
        public var radius: Double = 8.5
    }

    /// The page the map was drawn on, in pixels (the PDF keeps its proportions).
    public var width: Double
    public var height: Double
    public var rooms: [String: Room]
    /// Pairs of rooms joined by an exit or a ride.
    public var links: [[String]]
    /// Where the game starts.
    public var start: String?
    private var markerSpec: Marker?
    public var marker: Marker { markerSpec ?? Marker() }

    private enum CodingKeys: String, CodingKey {
        case width, height, rooms, links, start
        case markerSpec = "marker"
    }

    public init(width: Double = 1, height: Double = 1, rooms: [String: Room], links: [[String]]) {
        self.width = width
        self.height = height
        self.rooms = rooms
        self.links = links
    }

    public static func load(from url: URL) -> GameMap? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GameMap.self, from: data)
    }

    /// The ids of the rooms drawn with this name (more than one for Physical Plant and the
    /// elevators), in a stable order.
    public func ids(named name: String) -> [String] {
        rooms.filter { $0.value.name == name }.map(\.key).sorted()
    }

    public func neighbors(of id: String) -> Set<String> {
        Set(links.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return pair[0] == id ? pair[1] : pair[1] == id ? pair[0] : nil
        })
    }
}

/// "MAP" (and "show map", "look at the map"...): show the part of the map the player has
/// explored. Handled by the app; the game doesn't know the word.
public enum MapCommand {
    public static func matches(_ line: String) -> Bool {
        let filler: Set<String> = ["the", "my", "me", "a", "at", "please", "game"]
        let words = line.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty && !filler.contains($0) }
        guard let last = words.last, ["map", "maps"].contains(last) else { return false }
        let verbs: Set<String> = ["show", "open", "view", "see", "check", "display", "look", "read", "examine",
                                  "consult", "pull", "bring", "up"]
        return words.dropLast().allSatisfy { verbs.contains($0) }
    }
}

/// Follows which room on the map the player is in.
///
/// The game reports where the player goes by name (dfrotz's object trace says
/// `@move_obj player Physical Plant`; the status line names the room too), and a few names
/// belong to more than one room on the map. Those are told apart by where the player came
/// from: the Physical Plant next to the Mech Corridor, or the one off Systems Corridor East.
/// An elevator the player is riding switches ends when its door opens at the other one.
public struct MapPosition: Equatable, Sendable {
    /// The map room id the player is in, or nil before the game has said.
    public private(set) var room: String? {
        didSet { if let room { visited.insert(room) } }
    }
    /// Every map room the player has been in since the game started: what the "map" command shows.
    public private(set) var visited: Set<String> = []

    public init(room: String? = nil) {
        self.room = room
        if let room { visited = [room] }
    }

    /// The game prints this when an elevator the player is in arrives.
    static let elevatorArrives = "The elevator door slides open."

    public mutating func update(with turn: GameTurn, map: GameMap) {
        var moved = false
        for case .moved(let args) in turn.objectEvents where args.hasPrefix("player ") {
            let place = String(args.dropFirst("player ".count))
            // Moves into things in a room (the safety web, a bed) aren't on the map.
            if move(to: place, map: map) { moved = true }
        }
        if !moved, let location = turn.status?.location, room.flatMap({ map.rooms[$0]?.name }) != location {
            moved = move(to: location, map: map)
        }
        if !moved, turn.text.contains(Self.elevatorArrives), let here = room, let name = map.rooms[here]?.name,
           let otherEnd = map.ids(named: name).first(where: { $0 != here }) {
            room = otherEnd
        }
    }

    /// Moves to the room called `name`, if the map has one. Returns whether it did.
    @discardableResult
    public mutating func move(to name: String, map: GameMap) -> Bool {
        let candidates = map.ids(named: name)
        guard !candidates.isEmpty else { return false }
        if candidates.count == 1 {
            room = candidates[0]
        } else if let here = room, candidates.contains(here) {
            // Still there (the status line repeats the room every turn).
        } else if let here = room, let next = candidates.first(where: { map.neighbors(of: here).contains($0) }) {
            room = next
        } else {
            room = candidates[0]
        }
        return true
    }

    public mutating func reset() {
        room = nil
        visited = []
    }
}
