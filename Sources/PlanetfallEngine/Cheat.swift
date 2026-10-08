import Foundation

/// Cheat codes that jump to a moment in the story, for testing and demos: "cheat: pod",
/// "cheat: splash", and so on. Handled by the app, not the game.
///
/// A cheat doesn't restore a save file. It restarts the game with a fixed random seed and
/// replays a script of commands behind the scenes, like `Nap`, so everything the app tracks
/// (characters, story events, the safety web) is exactly right when it lands. Only the last
/// turn is shown.
public enum Cheat: String, CaseIterable, Sendable {
    case brig, explode, pod, splash

    /// The random seed every cheat replays with, so its script plays out the same each time.
    static let seed = 8

    enum Step: Equatable {
        /// Type a command.
        case send(String)
        /// WAIT until this text appears in a turn, giving up after `max` turns.
        case waitUntil(String, max: Int)
    }

    /// What the cheat does, shown when it's used.
    public var summary: String {
        switch self {
        case .brig: "Thrown in the brig by Ensign Blather."
        case .explode: "The Feinstein has just started to explode."
        case .pod: "Strapped into the escape pod's webbing as the ship blows up."
        case .splash: "The escape pod has landed and sunk. You're swimming out."
        }
    }

    var steps: [Step] {
        let explosion = Step.waitUntil("A massive explosion rocks the ship", max: 20)
        switch self {
        case .brig:
            return [.send("up"), .send("up"), .waitUntil("drags you to the Feinstein's brig", max: 10)]
        case .explode:
            return [explosion]
        case .pod:
            return [explosion, .send("west"), .send("get in webbing")]
        case .splash:
            return [explosion, .send("west"), .send("get in webbing"),
                    .waitUntil("The pod lands with a thud", max: 30),
                    .send("get out of webbing"), .send("open door"), .send("up")]
        }
    }

    public enum Request: Equatable, Sendable {
        case cheat(Cheat)
        /// "cheat: xyz" with a name that isn't a cheat.
        case unknown(String)
    }

    /// The cheat `line` asks for: "cheat: pod", "Cheat pod", "cheat:splash", or as speech-to-text
    /// writes it ("Cheat, pod.", "cheat code splash", "cheat brick"). Nil if it isn't a cheat
    /// command at all.
    public static func request(in line: String) -> Request? {
        let words = line.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        guard words.first == "cheat" else { return nil }
        var rest = words.dropFirst()
        if rest.first == "code" { rest = rest.dropFirst() }
        let name = rest.joined(separator: " ")
        if let cheat = Cheat(rawValue: name) ?? spokenAliases[name] { return .cheat(cheat) }
        return .unknown(name)
    }

    /// Names speech-to-text tends to produce instead of the cheat's.
    static let spokenAliases: [String: Cheat] = [
        "brick": .brig, "the brig": .brig,
        "explosion": .explode, "exploding": .explode, "explodes": .explode, "boom": .explode,
        "pods": .pod, "the pod": .pod, "escape pod": .pod,
        "splashed": .splash, "splashes": .splash, "underwater": .splash,
    ]

    static var list: String {
        allCases.map { "cheat: \($0.rawValue)" }.joined(separator: ", ")
    }
}
