import Foundation
import Testing
@testable import PlanetfallEngine

/// The ambassador is never quoted; the game reports what he says, and each report becomes a line
/// he speaks through his translator.
struct AmbassadorVoiceTests {
    private let voices = VoiceCast.defaults.characters

    @Test(arguments: [
        ("The ambassador introduces himself as Br'gun-te'elkner-ipg'nun.", "Greetings. I am Br'gun-te'elkner-ipg'nun."),
        ("The ambassador asks if you are performing some sort of religious ceremony.", "Are you performing some sort of religious ceremony?"),
        ("The ambassador inquires whether you are interested in a game of Bocci.", "Would you be interested in a game of Bocci?"),
        ("The ambassador recites a plea for coexistence between your races.", "[solemnly] Let our two great races live side by side, in peace."),
        ("The ambassador asks where Admiral Smithers can be found.", "Where can Admiral Smithers be found?"),
        ("The ambassador remarks that all humans look alike to him.", "Forgive me. All humans look alike to me."),
        ("The ambassador offers you a bit of celery.", "Would you care for a bit of celery?"),
    ])
    func speaksEachOfHisRandomLines(turn: String, expected: String) {
        let script = DialogueExtractor.script(for: turn, voices: voices)
        #expect(script.lines.map(\.characterID) == ["ambassador"])
        #expect(script.lines.first?.ttsText == expected)
        // The narrator knows he spoke, but not what he said.
        #expect(script.narration == "The ambassador [Ambassador speaks].")
    }

    @Test func wheezesAGreetingWhenHeArrives() {
        // As dfrotz prints it: one paragraph wrapped at 255 columns.
        let turn = """
            The alien ambassador from the planet Blow'k-bibben-Gordo ambles toward you from down the corridor. He is munching on something resembling an enormous stalk of celery, and he leaves a trail of green slime on the deck. He stops nearby, and you wince as a
            pool of slime begins forming beneath him on your newly-polished deck. The ambassador wheezes loudly and hands you a brochure outlining his planet's major exports.
            """
        let script = DialogueExtractor.script(for: turn, voices: voices)
        #expect(script.lines == [SpokenLine(characterID: "ambassador",
                                            text: "Greetings, ensign. A gift from Blow'k-bibben-Gordo.",
                                            ttsText: "[wheezing] Greetings, ensign. A gift from Blow'k-bibben-Gordo.")])
        #expect(script.narration.hasSuffix("The ambassador [Ambassador speaks] and hands you a brochure outlining his planet's major exports."))
    }

    @Test(arguments: [
        ("The ambassador grunts a polite farewell, and disappears up the gangway, leaving a trail of dripping slime.",
         "[grunting] Farewell, ensign."),
        ("The door to port slides open. The ambassador squawks frantically, evacuates a massive load of gooey slime, and rushes away.",
         "[squawking frantically] Squawk! Squawk!"),
        ("The ambassador whimpers and slaps your wrist.", "[whimpering] Please, not the translator!"),
    ])
    func voicesHisSounds(turn: String, expected: String) {
        #expect(DialogueExtractor.lines(in: turn, voices: voices).map(\.ttsText) == [expected])
    }

    @Test func leavesHisBrochureAndGesturesToTheNarrator() {
        let turns = [
            #""The leading export of Blow'k-bibben-Gordo is the adventure game *** PLANETFALL *** written by S. Eric Meretzky. Buy one today. Better yet, buy a thousand.""#,
            "The ambassador taps his translator, and then touches his center knee to his left ear (the Blow'k-bibben-Gordoan equivalent of shrugging).",
            "The ambassador seems perturbed by your lack of normal protocol.",
        ]
        for turn in turns {
            let script = DialogueExtractor.script(for: turn, voices: voices)
            #expect(script.lines.isEmpty, "\(turn)")
            #expect(script.narration == turn)
        }
    }

    /// The real game: with seed 10 the ambassador arrives on the first wait, speaks on the next
    /// three, and says goodbye on the fifth.
    @MainActor
    @Test(.enabled(if: GameLocator.dfrotzURL() != nil && GameLocator.storyURL() != nil))
    func speaksThroughoutARealVisit() async throws {
        let saves = FileManager.default.temporaryDirectory.appendingPathComponent("planetfall-ambassador-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: saves) }
        let session = GameSession(dfrotzURL: GameLocator.dfrotzURL()!, storyURL: GameLocator.storyURL()!,
                                  savesDirectory: saves, randomSeed: 10)
        var lines: [String] = []
        var turns = 0
        session.addObserver { event in
            guard case .turn(let turn) = event else { return }
            turns += 1
            lines += DialogueExtractor.lines(in: turn.text, voices: VoiceCast.defaults.characters)
                .filter { $0.characterID == "ambassador" }.map(\.ttsText)
        }
        try session.start()
        defer { session.stop() }
        for expected in 1...6 {
            for _ in 0..<100 where turns < expected { try await Task.sleep(for: .milliseconds(50)) }
            if expected < 6 { session.send("wait") }
        }
        #expect(lines == [
            "[wheezing] Greetings, ensign. A gift from Blow'k-bibben-Gordo.",
            "Would you care for a bit of celery?",
            "Where can Admiral Smithers be found?",
            "[solemnly] Let our two great races live side by side, in peace.",
            "[grunting] Farewell, ensign.",
        ])
    }
}
