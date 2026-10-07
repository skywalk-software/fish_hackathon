import Testing
@testable import PlanetfallEngine

struct FrotzOutputParserTests {
    private let status = " Deck Nine                                        Score: 0        Moves: 4454"

    @Test func splitsOpeningTurnAtPrompt() {
        var parser = FrotzOutputParser()
        let turns = parser.consume("\(status)\n\nPLANETFALL\nRelease 39\n\nDeck Nine\nA corridor.\n\n>")
        #expect(turns.count == 1)
        #expect(turns[0].text == "PLANETFALL\nRelease 39\n\nDeck Nine\nA corridor.")
        #expect(turns[0].status == StatusLine(location: "Deck Nine", score: 0, moves: 4454))
        #expect(turns[0].prompt == .command)
        #expect(!parser.hasPendingOutput)
    }

    @Test func handlesPromptSplitAcrossChunks() {
        var parser = FrotzOutputParser()
        #expect(parser.consume("\(status)\n\nTime passes...\n").isEmpty)
        let turns = parser.consume("\n>")
        #expect(turns.map(\.text) == ["Time passes..."])
    }

    @Test func handlesTwoTurnsInOneChunk() {
        var parser = FrotzOutputParser()
        let turns = parser.consume("\(status)\n\nOne.\n\n>\(status)\n\nTwo.\n\n>")
        #expect(turns.map(\.text) == ["One.", "Two."])
    }

    @Test func flushesNonCommandPrompt() {
        var parser = FrotzOutputParser()
        #expect(parser.consume("\(status)\n\nPlease enter a filename [planetfall.qzl]: ").isEmpty)
        let turn = parser.flushPending()
        #expect(turn?.text == "Please enter a filename [planetfall.qzl]: ")
        #expect(turn?.prompt == .question)
        #expect(parser.flushPending() == nil)
    }

    @Test func parsesMultiWordLocationAndNegativeScore() {
        let line: Substring = " Escape Pod      Score: -5     Moves: 12"
        #expect(FrotzOutputParser.parseStatusLine(line) == StatusLine(location: "Escape Pod", score: -5, moves: 12))
        #expect(FrotzOutputParser.parseStatusLine("You are carrying:") == nil)
    }

    @Test func extractsObjectEventsFromText() {
        var parser = FrotzOutputParser()
        let turns = parser.consume("""
        \(status)

        Time passes...
           @move_obj Ensign First Class Deck Nine

        Ensign First Class Blather swaggers in.
        The door slides open.   @remove_obj Ensign First Class

        >
        """)
        #expect(turns.count == 1)
        #expect(turns[0].objectEvents == [.moved("Ensign First Class Deck Nine"), .removed("Ensign First Class")])
        #expect(turns[0].text == "Time passes...\n\nEnsign First Class Blather swaggers in.\nThe door slides open.")
    }

    @Test func tracksCharacterLocations() {
        var locations: [String: String] = [:]
        GameCharacter.apply(.moved("Ensign First Class Deck Nine"), to: &locations)
        GameCharacter.apply(.moved("multiple purpose robot Robot Shop"), to: &locations)
        GameCharacter.apply(.moved("player Gangway"), to: &locations)
        #expect(locations == ["blather": "Deck Nine", "floyd": "Robot Shop"])
        GameCharacter.apply(.removed("Ensign First Class"), to: &locations)
        #expect(locations == ["floyd": "Robot Shop"])
    }
}
