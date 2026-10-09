import Testing
@testable import PlanetfallEngine

struct DialogueAttributionTests {
    private let voices = VoiceCast.defaults.characters

    @Test func buttonLabelsArentSpeech() {
        let text = "Standing against the rear wall is a large dispensing machine with a spout. One of these is square and says \"BAAS.\" The other white button is round and says \"ASID.\" Floyd follows you."
        #expect(DialogueExtractor.lines(in: text, voices: voices).isEmpty)
    }

    @Test func aNameAfterAQuoteNeedsASpeechVerb() {
        let spoken = DialogueExtractor.lines(in: "\"Let's play!\" says Floyd.", voices: voices)
        #expect(spoken.map(\.characterID) == ["floyd"])
        #expect(DialogueExtractor.lines(in: "\"Exit\" glows over the door. Floyd follows you.", voices: voices).isEmpty)
    }

    @Test func floydsWakeUpLineIsHis() {
        let text = "Suddenly, the robot comes to life and its head starts swivelling about. It notices you and bounds over. \"Hi! I'm B-19-7, but to everyperson I'm called Floyd. Let's play Hider-and-Seeker you with me.\""
        let lines = DialogueExtractor.lines(in: text, voices: voices)
        #expect(lines.map(\.characterID) == ["floyd"])
        #expect(lines.first?.text.hasPrefix("Hi! I'm B-19-7") == true)
    }
}
