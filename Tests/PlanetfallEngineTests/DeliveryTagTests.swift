import Foundation
import Testing
@testable import PlanetfallEngine

struct DeliveryTagTests {
    @Test func stripsTagsIncludingOneStillBeingWritten() {
        #expect(DeliveryTags.strip("[dripping with sarcasm] Oh, splendid. [deadpan] Truly.") == "Oh, splendid. Truly.")
        #expect(DeliveryTags.strip("Oh, splendid. [dripping wi") == "Oh, splendid.")
        #expect(DeliveryTags.strip("[warm") == "")
        #expect(DeliveryTags.strip("No tags here.") == "No tags here.")
    }

    @Test func aTaggedPassIsStillAPass() {
        var pass = Commentator.PassFilter()
        #expect(pass.feed("[dead") == nil)
        #expect(pass.feed("pan] PA") == nil)
        #expect(pass.feed("SS") == nil)
        #expect(pass.finish() == nil)

        // A real quip keeps its tag for the voice actor.
        var quip = Commentator.PassFilter()
        #expect(quip.feed("[mock-impressed] ") == nil)  // only a tag so far
        let shown = [quip.feed("PA"), quip.feed("TIENCE, at last.")].compactMap { $0 }
        #expect(shown.joined() == "[mock-impressed] PATIENCE, at last.")
    }

    @Test func aTaggedSkipIsStillASkip() {
        var skip = NarrationFilter()
        #expect(skip.feed("[wry] SKIP").isEmpty)
        #expect(skip.finish().isEmpty)

        var narration = NarrationFilter()
        let first = narration.feed("[warm] You step into a featureless corridor on Deck Nine. [wry] Again.")
        #expect(first == ["[warm] You step into a featureless corridor on Deck Nine."])
        #expect(narration.finish() == ["[wry] Again."])
    }

    @Test func narratorSpeedGoesToFishAndCanBeOverridden() throws {
        let request = FishTextToSpeech(apiKey: "k").makeRequest(text: "Hi", voiceID: "v", speed: 1.1)
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((body["prosody"] as? [String: Double])?["speed"] == 1.1)
        let plain = FishTextToSpeech(apiKey: "k").makeRequest(text: "Hi", voiceID: "v")
        let plainData = try #require(plain.httpBody)
        let plainBody = try #require(try JSONSerialization.jsonObject(with: plainData) as? [String: Any])
        #expect(plainBody["prosody"] == nil)

        let envFile = FileManager.default.temporaryDirectory.appendingPathComponent("env-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: envFile) }
        #expect(VoiceCast.load(environment: [:], envFile: envFile).narratorSpeed == 1.1)
        #expect(VoiceCast.load(environment: ["FISH_SPEED_NARRATOR": "1.2"], envFile: envFile).narratorSpeed == 1.2)
    }
}
