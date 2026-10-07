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

## Voice commands (push-to-talk)

**Setup:** put your keys in `.env` at the repo root. Get a Fish Audio key at https://fish.audio/app/api-keys and an Anthropic key at https://console.anthropic.com.

```sh
FISH_API_KEY=your-fish-key
ANTHROPIC_API_KEY=your-anthropic-key   # optional: Claude command cleanup
```

- `.env` is gitignored, so never commit it.
- Environment variables with the same names override the file.
- Without `FISH_API_KEY`, the game still runs, but the mic button stays disabled.
- Without `ANTHROPIC_API_KEY`, voice still works, but commands go to the game exactly as heard.

**Using it:**
- **Hold ⌥ (Option)**, or hold the mic button next to the command line, and speak a command. Release to send.
- The clip goes to Fish speech-to-text (`POST /v1/asr`, model `transcribe-1-pro`). A short "go north" took about 0.1–0.3 s round trip in testing.
- **Command cleanup:** Claude then turns what you said into a command the parser understands, and that's sent to the game as if you had typed it. It's also added to the ↑/↓ history.
  - Filler and polite padding go: "um, could you open the door and then go north" becomes `open door. north`.
  - Misheard nouns get fixed from what's on screen: "take the kid" next to a survey kit becomes `take kit`.
  - It answers the game's own questions (yes/no, save file names).
  - It doesn't play for you: it never adds actions, directions or objects you didn't say.
  - When the command differs from what you said, the input field shows `Heard "…"` so you can see what happened.
  - If you weren't giving a command ("hmm, let me think"), nothing is sent.
  - If Claude can't be reached, the transcript is sent as heard and the input field says why.

**Notes:**
- **Microphone permission:** the first time you press ⌥, macOS asks for microphone access. With `swift run`, the prompt names Terminal (or whichever app launched it). The built app asks for itself.
- **Accidental presses:** holds under 0.3 s are ignored, and so is silence, so it doesn't spend API calls. Pressing another key while holding ⌥ (to type a special character or use a shortcut) cancels the recording.
- **Why push-to-talk:** Fish's speech-to-text has no streaming endpoint. It transcribes one finished clip per request, so you have to mark when you're done talking.
- **Cost:** speech-to-text costs $0.36 per audio hour.
- **Cleanup model:** `claude-opus-5-5` at `effort: "low"`, with a cached system prompt and JSON-schema output. It adds a round trip on top of speech-to-text. For lower latency, construct `CommandInterpreter(apiKey:model:effort:serverSideFallbacks:)` with `model: "claude-haiku-4-5", effort: nil, serverSideFallbacks: false` in `PushToTalk`.
- **Live tests:** run the opt-in tests against the real APIs with `FISH_LIVE_TESTS=1 swift test --filter transcribesRealSpeech` and `ANTHROPIC_LIVE_TESTS=1 swift test --filter interpretsRealSpeech`.

## How it works

We don't port the game. `planetfall.z3` is Infocom's compiled game (Release 39), which runs on a Z-machine interpreter. The app runs **dfrotz** in the background and passes text in and out over pipes.

| Piece | File | Job |
|---|---|---|
| `FrotzOutputParser` | [Sources/PlanetfallEngine/FrotzOutputParser.swift](Sources/PlanetfallEngine/FrotzOutputParser.swift) | Splits dfrotz output into turns at the `>` prompt and pulls out the status line (room, score, moves). |
| `GameSession` | [Sources/PlanetfallEngine/GameSession.swift](Sources/PlanetfallEngine/GameSession.swift) | Owns the dfrotz process. Exposes observable state (`transcript`, `status`, `isAwaitingInput`) and an event stream. |
| `GameLocator` | [Sources/PlanetfallEngine/GameLocator.swift](Sources/PlanetfallEngine/GameLocator.swift) | Finds dfrotz and the story file. Override with `DFROTZ_PATH` / `PLANETFALL_STORY`. |
| `FishAPIKey`, `AnthropicAPIKey` | [Sources/PlanetfallEngine/FishAPIKey.swift](Sources/PlanetfallEngine/FishAPIKey.swift) | Load `FISH_API_KEY` / `ANTHROPIC_API_KEY` from the environment, then from `.env`. |
| `FishSpeechToText` | [Sources/PlanetfallEngine/FishSpeechToText.swift](Sources/PlanetfallEngine/FishSpeechToText.swift) | Uploads a WAV to Fish `POST /v1/asr` and returns a clean command (speaker markers and cues removed). |
| `CommandInterpreter` | [Sources/PlanetfallEngine/CommandInterpreter.swift](Sources/PlanetfallEngine/CommandInterpreter.swift) | Sends what was heard, plus the current room and recent output (`GameSession.commandContext()`), to Claude and returns one parser command. |
| `WAV` | [Sources/PlanetfallEngine/WAV.swift](Sources/PlanetfallEngine/WAV.swift) | Encodes recorded samples as 16-bit mono WAV. |
| `PushToTalk`, `MicrophoneRecorder` | [Sources/Planetfall/](Sources/Planetfall/) | Hold-⌥ / mic-button recording with AVAudioEngine, then speech-to-text, then command cleanup, then `session.send`. |
| App UI | [Sources/Planetfall/](Sources/Planetfall/) | SwiftUI window: status bar, room art, transcript, command line with ↑/↓ history and a mic button. |
| `Commentator`, `Sidekick` | [Sources/PlanetfallEngine/](Sources/PlanetfallEngine/) | Let's-play commentary: streams a quip from Claude after each turn. `Sidekick` decides when to comment. |
| `GameCharacter` | [Sources/PlanetfallEngine/GameCharacter.swift](Sources/PlanetfallEngine/GameCharacter.swift) | The game's characters (Blather, Floyd, the ambassador…) and the in-game object names used to track them. |
| `Artwork` | [Sources/Planetfall/Artwork.swift](Sources/Planetfall/Artwork.swift) | Finds the illustration for a room or character. |

`PlanetfallEngine` has no UI code, so voice features can build on it directly.

## Room art

When you're in a room that has art, the app shows it above the transcript and crossfades between rooms. Rooms without art just show text.

To add art, drop an image into [Art/Rooms/](Art/Rooms/), named after the room as it appears in the status bar: lowercase, with hyphens between words. For example, **Deck Nine** → `deck-nine.jpg` and **Escape Pod** → `escape-pod.png`. JPG, PNG and WebP work, and about 16:9 crops best. No code changes are needed. `swift run` picks images up from the repo, and `build-app.sh` copies them into the app.

## Character portraits

When a character is in the same room as you, their portrait appears in the top-right corner. Several characters can appear at once, side by side. Click a portrait to see it close up, filling the window; close it with the ✕ or Escape. This way room art never has to be drawn both with and without each character.

The app knows where characters are because dfrotz runs with `-o`, which reports every object the game moves (`@move_obj Ensign First Class Deck Nine`). The engine strips those lines from the narration and keeps `session.characterLocations` up to date. A portrait stays up while the character is present, even on turns that don't mention them.

To add a portrait, drop a square image into [Art/NPCs/](Art/NPCs/), named by the character's `id`:

| id | Character | In-game object name |
|---|---|---|
| `blather` | Ensign Blather | Ensign First Class |
| `ambassador` | Alien Ambassador | alien ambassador |
| `floyd` | Floyd | multiple purpose robot |
| `rat-ant` | Rat-Ant | rat-like, ant-like man-sized monster |
| `troll` | Hairy Biped | hairy growling biped |
| `grue` | Grue | lurking fanged creature |
| `microbe` | Microbe | microbe |

A head-and-shoulders shot on a plain dark background works best at inset size.

The opening is random: on Deck Nine, the game sends Blather, the alien ambassador, or nobody. Pass `randomSeed:` to `GameSession` to get the same game every time. For example, with seed 8, Blather arrives on turn 4.

## Sidekick commentary

**SNARK-9**, a jaded retro-gaming commentary robot, co-hosts your playthrough like a let's-play sidekick. It isn't part of the game: it watches you play from outside, the way a viewer would, and can't be seen or talked to in Planetfall. After each turn, the app sends the recent game output to Claude (`claude-opus-5-5`, low effort, streamed). SNARK-9's reaction types out live in a bar above the command line. It passes on routine turns, so it doesn't comment on everything.

- **Setup:** it needs `ANTHROPIC_API_KEY` in `.env`. Without a key, the bar is hidden.
- **Turning it off:** use **Sidekick → SNARK-9 Commentary** (⇧⌘K). The setting is remembered between launches.
- **Recasting the sidekick:** edit `SidekickPersona.default` in [Sources/PlanetfallEngine/Commentator.swift](Sources/PlanetfallEngine/Commentator.swift) to change the name, description and personality. The rules (short, no spoilers, PG-13, no invented events) are in the system prompt in the same file.
- **Avatar:** drop a square image at `Art/NPCs/sidekick.jpg`. Until then, the bar shows an icon.
- **Pacing:** if you type while a quip is still streaming, the sidekick finishes it, then comments once on the latest state, so quips never pile up.
- **Cost:** each commented turn sends about 1–3K input tokens, roughly a cent or two per turn.
- **Live test:** run it against the real API with `ANTHROPIC_LIVE_TESTS=1 swift test --filter commentsOnARealTurn`.

**For voice:** `sidekick.onLineFinished { line in … }` delivers each finished quip, ready to speak in SNARK-9's own Fish voice. `sidekick.line` updates as the text streams, if you'd rather start speaking sooner.

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

// Voice input is already wired up: PushToTalk sends each cleaned-up command with
session.send("open the pod")
```

`session.presentCharacters` lists who is in the room right now, and `turn.objectEvents` has the raw movements for that turn. Use them to pick a character's voice.

Notes for voice:
- **Text output**: dfrotz runs 255 columns wide, so paragraphs rarely contain hard line breaks. Lists (like inventory) do keep their newlines. The first turn also includes the title/copyright banner, which you may want to skip.
- **Floyd** speaks in quotes after "Floyd says" and similar phrases, so a regex is probably enough to give him his own voice.
- **Fish API**: see section 7.2 and section 11 of the deep dive. `s2.1-pro-free` costs $0 until 2026-11-30. Fish has no Swift SDK, so call `POST /v1/tts` directly with `URLSession`, and play the audio with `AVAudioPlayer` or `AVAudioEngine`.
- **Speech input**: already done with Fish speech-to-text push-to-talk plus Claude command cleanup (see [Voice commands](#voice-commands-push-to-talk)). If you add TTS narration, stop playback when a `.command` event arrives, so the narrator doesn't talk over the player.

## Licensing

The Planetfall source and story file come from [historicalsource/planetfall](https://github.com/historicalsource/planetfall) and are **not openly licensed**. That's why `Story/planetfall.z3` is downloaded by script rather than committed. Fine for a hackathon demo; don't distribute builds publicly.
