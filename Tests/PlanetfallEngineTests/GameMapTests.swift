import Foundation
import Testing
@testable import PlanetfallEngine

struct MapPositionTests {
    /// A corner of the real map: both Physical Plants, and the blue elevator at both ends.
    let map = GameMap(
        rooms: [
            "MECH-CORRIDOR-N": .init(name: "Mech Corridor North"),
            "PHYSICAL-PLANT": .init(name: "Physical Plant"),
            "SYSTEMS-CORRIDOR-EAST": .init(name: "Systems Corridor East"),
            "PHYSICAL-PLANT-TWO": .init(name: "Physical Plant"),
            "ELEVATOR-LOBBY": .init(name: "Elevator Lobby"),
            "UPPER-ELEVATOR": .init(name: "Upper Elevator"),
            "UPPER-ELEVATOR@top": .init(name: "Upper Elevator"),
            "TOWER-CORE": .init(name: "Tower Core"),
        ],
        links: [["MECH-CORRIDOR-N", "PHYSICAL-PLANT"], ["PHYSICAL-PLANT-TWO", "SYSTEMS-CORRIDOR-EAST"],
                ["ELEVATOR-LOBBY", "UPPER-ELEVATOR"], ["UPPER-ELEVATOR", "UPPER-ELEVATOR@top"],
                ["TOWER-CORE", "UPPER-ELEVATOR@top"]])

    func moved(to room: String, text: String = "") -> GameTurn {
        GameTurn(text: text, status: StatusLine(location: room, score: 0, moves: 1), prompt: .command,
                 objectEvents: [.moved("player \(room)")])
    }

    @Test func namesTheRoomFromThePlayersMove() {
        var position = MapPosition()
        position.update(with: moved(to: "Mech Corridor North"), map: map)
        #expect(position.room == "MECH-CORRIDOR-N")
    }

    @Test func tellsTheTwoPhysicalPlantsApartByWhereThePlayerCameFrom() {
        var position = MapPosition(room: "SYSTEMS-CORRIDOR-EAST")
        position.update(with: moved(to: "Physical Plant"), map: map)
        #expect(position.room == "PHYSICAL-PLANT-TWO")

        position = MapPosition(room: "MECH-CORRIDOR-N")
        position.update(with: moved(to: "Physical Plant"), map: map)
        #expect(position.room == "PHYSICAL-PLANT")
    }

    @Test func staysPutWhenTheStatusLineRepeatsTheRoom() {
        var position = MapPosition(room: "PHYSICAL-PLANT-TWO")
        position.update(with: GameTurn(text: "Time passes.", status: StatusLine(location: "Physical Plant", score: 0, moves: 2),
                                       prompt: .command), map: map)
        #expect(position.room == "PHYSICAL-PLANT-TWO")
    }

    @Test func ignoresMovesIntoThingsThatArentRooms() {
        var position = MapPosition(room: "TOWER-CORE")
        position.update(with: GameTurn(text: "", status: nil, prompt: .command,
                                       objectEvents: [.moved("player safety web")]), map: map)
        #expect(position.room == "TOWER-CORE")
    }

    @Test func theElevatorChangesEndsWhenItsDoorOpensAtTheOther() {
        var position = MapPosition(room: "ELEVATOR-LOBBY")
        position.update(with: moved(to: "Upper Elevator"), map: map)
        #expect(position.room == "UPPER-ELEVATOR")
        let ride = GameTurn(text: "The elevator door slides open.",
                            status: StatusLine(location: "Upper Elevator", score: 0, moves: 9), prompt: .command)
        position.update(with: ride, map: map)
        #expect(position.room == "UPPER-ELEVATOR@top")
        position.update(with: moved(to: "Tower Core"), map: map)
        #expect(position.room == "TOWER-CORE")
        position.update(with: moved(to: "Upper Elevator"), map: map)
        #expect(position.room == "UPPER-ELEVATOR@top")
    }

    @Test func theRealMapLoadsAndHasEveryRoom() throws {
        let url = GameLocator.repoRoot.appendingPathComponent("Art/Map/planetfall-map.json")
        let map = try #require(GameMap.load(from: url))
        #expect(map.rooms.count == 107)
        #expect(map.ids(named: "Physical Plant") == ["PHYSICAL-PLANT", "PHYSICAL-PLANT-TWO"])
        #expect(map.neighbors(of: "PHYSICAL-PLANT").contains("MECH-CORRIDOR-N"))
    }

    @Test func cheatMapAsksForTheMap() {
        #expect(Cheat.request(in: "cheat: map") == .map)
        #expect(Cheat.request(in: "Cheat, map.") == .map)
        #expect(Cheat.list.contains("cheat: map"))
    }
}

/// Following the player around the real game. Skipped without dfrotz or the story file.
@MainActor
@Suite(.enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
struct MapPositionGameTests {
    @Test func followsThePlayerFromACheatAndShowsTheMapWithoutRestarting() async throws {
        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!, storyURL: GameLocator.storyURL()!,
                                  savesDirectory: FileManager.default.temporaryDirectory, randomSeed: 3)
        session.map = GameMap.load(from: GameLocator.repoRoot.appendingPathComponent("Art/Map/planetfall-map.json"))
        var count = 0
        session.addObserver { if case .turn = $0 { count += 1 } }
        func play(_ command: String) async throws {
            let target = count + 1
            session.send(command)
            for _ in 0..<400 where count < target { try await Task.sleep(for: .milliseconds(20)) }
        }
        try session.start()
        defer { session.stop() }
        for _ in 0..<100 where count == 0 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(session.mapPosition.room == "DECK-NINE")

        try await play("cheat: floyd")
        #expect(session.mapPosition.room == "ROBOT-SHOP")
        try await play("west")
        #expect(session.mapPosition.room == "MACHINE-SHOP")

        session.send("cheat: map")
        #expect(session.isShowingMap)
        #expect(session.mapPosition.room == "MACHINE-SHOP")
        #expect(session.status?.location == "Machine Shop")
    }
}
