# fish_hackathon

Hackathon workspace for building with Fish Audio speech models. We're building a native Mac version of Infocom's **Planetfall** (1983) and adding Fish Audio voices.

- [fish_speech_deep_dive.md](fish_speech_deep_dive.md): research notes on Fish Speech / Fish Audio. Covers S2-Pro and S2.1-Pro TTS, the status of ASR and speech-to-speech, voice cloning, multilingual support, local setup, the local and cloud APIs, limitations, and a comparison with Tencent AuK and other alternatives.

## Running the game

You need macOS 14+, Xcode (Swift 6), and Homebrew.

```sh
brew install frotz           # provides dfrotz, the text-only Z-machine interpreter
./scripts/fetch-story.sh     # downloads Story/planetfall.z3 (not committed; see below)
swift run Planetfall         # or: open Package.swift in Xcode and run the Planetfall scheme
```

To build a double-clickable app instead, run `./scripts/build-app.sh` and open `build/Planetfall.app`. The app still uses dfrotz from Homebrew.

Run the tests with `swift test`. One test plays real turns through dfrotz.

Save files go in `~/Library/Application Support/Planetfall/Saves`. Restart the game with ⇧⌘R.

## How it works

We don't port the game. `planetfall.z3` is Infocom's compiled game (Release 39), which runs on a Z-machine interpreter. The app runs **dfrotz** in the background and passes text in and out over pipes.

| Piece | File | Job |
|---|---|---|
| `FrotzOutputParser` | [Sources/PlanetfallEngine/FrotzOutputParser.swift](Sources/PlanetfallEngine/FrotzOutputParser.swift) | Splits dfrotz output into turns at the `>` prompt and pulls out the status line (room, score, moves). |
| `GameSession` | [Sources/PlanetfallEngine/GameSession.swift](Sources/PlanetfallEngine/GameSession.swift) | Owns the dfrotz process. Exposes observable state (`transcript`, `status`, `isAwaitingInput`) and an event stream. |
| `GameLocator` | [Sources/PlanetfallEngine/GameLocator.swift](Sources/PlanetfallEngine/GameLocator.swift) | Finds dfrotz and the story file. Override with `DFROTZ_PATH` / `PLANETFALL_STORY`. |
| App UI | [Sources/Planetfall/](Sources/Planetfall/) | SwiftUI window: status bar, room art, transcript, command line with ↑/↓ history. |
| `RoomArt` | [Sources/Planetfall/RoomArt.swift](Sources/Planetfall/RoomArt.swift) | Finds the illustration for the current room. |

`PlanetfallEngine` has no UI code, so voice features can build on it directly.

## Room art

When you're in a room that has art, the app shows it above the transcript and crossfades between rooms. Rooms without art just show text.

To add art, drop an image into [Art/Rooms/](Art/Rooms/), named after the room as it appears in the status bar: lowercase, with hyphens between words. For example, **Deck Nine** → `deck-nine.jpg` and **Escape Pod** → `escape-pod.png`. JPG, PNG and WebP work, and about 16:9 crops best. No code changes are needed. `swift run` picks images up from the repo, and `build-app.sh` copies them into the app.

## Hooking up voice

`GameSession` is the integration point. Everything happens on the main actor.

```swift
session.addObserver { event in
    switch event {
    case .turn(let turn):
        // The game finished responding. turn.text is the narration for this turn
        // (status line already removed), turn.status has the current room.
        // turn.prompt is .command for the normal ">" prompt, or .question for
        // things like the save-filename prompt.
        Task { await narrator.speak(turn.text) }   // e.g. Fish TTS
    case .command(let line):
        break   // the player or voice input sent a command; stop any playing audio here
    case .ended:
        break
    }
}

// Voice input: once speech is transcribed, send it like typed input.
session.send("open the pod")
```

Notes for voice:
- **Text output**: dfrotz runs 255 columns wide, so paragraphs rarely contain hard line breaks. Lists (like inventory) do keep their newlines. The first turn also includes the title/copyright banner, which you may want to skip.
- **Floyd** speaks in quotes after "Floyd says" and similar phrases, so a regex is probably enough to give him his own voice.
- **Fish API**: see section 7.2 and section 11 of the deep dive. `s2.1-pro-free` costs $0 until 2026-11-30. Fish has no Swift SDK, so call `POST /v1/tts` directly with `URLSession`, and play the audio with `AVAudioPlayer` or `AVAudioEngine`.
- **Speech input**: Fish's cloud ASR is batch-only. Apple's on-device speech recognition (`Speech` framework) streams, is free, and works offline.

## Licensing

The Planetfall source and story file come from [historicalsource/planetfall](https://github.com/historicalsource/planetfall) and are **not openly licensed**. That's why `Story/planetfall.z3` is downloaded by script rather than committed. Fine for a hackathon demo; don't distribute builds publicly.
