# fish_hackathon

Hackathon workspace for building with Fish Audio speech models. We're building a native Mac version of Infocom's **Planetfall** (1983) and adding Fish Audio voices.

- [fish_speech_deep_dive.md](fish_speech_deep_dive.md): research notes on Fish Speech / Fish Audio. Covers S2-Pro and S2.1-Pro TTS, the status of ASR and speech-to-speech, voice cloning, multilingual support, local setup, the local and cloud APIs, limitations, and a comparison with Tencent AuK and other alternatives.

## Install with Homebrew

```sh
brew install skywalk-software/planetfall/planetfall
planetfall
```

- **What it installs:** Homebrew installs `frotz` (the interpreter), builds `Planetfall.app` from this repo, and downloads the game file (Release 39) from [historicalsource/planetfall](https://github.com/historicalsource/planetfall).
  - Homebrew doesn't carry Infocom's games, and this repo doesn't include the game file.
  - The formula lives in [skywalk-software/homebrew-planetfall](https://github.com/skywalk-software/homebrew-planetfall).
- **Requirements:** macOS 14+ and Swift 6 (Xcode 16+ or its Command Line Tools), since the app is built on your Mac.
- **Launching:** `planetfall` opens the app. To add it to Applications, run `ln -sf "$(brew --prefix)/opt/planetfall/Planetfall.app" /Applications/`.
- **Voices:** put your keys in `~/Library/Application Support/Planetfall/.env`, in the same format as [Voice commands](#voice-commands-push-to-talk).
- **Updating:** `brew upgrade planetfall`. To install the latest `main` instead of the release, use `brew install --HEAD skywalk-software/planetfall/planetfall`.

## Running the game from source

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

**Setup:** put your keys in `.env` at the repo root, or in `~/Library/Application Support/Planetfall/.env` for a Homebrew install. Get a Fish Audio key at https://fish.audio/app/api-keys and an Anthropic key at https://console.anthropic.com.

```sh
FISH_API_KEY=your-fish-key
ANTHROPIC_API_KEY=your-anthropic-key   # optional: Claude command cleanup
```

- `.env` is gitignored, so never commit it.
- Environment variables with the same names override the file.
- Without `FISH_API_KEY`, the game still runs, but the mic button stays disabled.
- Without `ANTHROPIC_API_KEY`, voice still works, but there's no cleanup: a transcript reaches the game only if every word in it is already in the game's vocabulary.

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
  - **Only accepted text is sent.** Before anything reaches the game, every word is checked against the parser's own dictionary, read from `planetfall.z3` (668 words, compared by their first six letters the way the game does).
    - A command with an unknown word is held back ("Not sent: the game doesn't know "please""), so the game never answers "I don't know the word".
    - Claude gets the same vocabulary, so it writes commands using only those words.
    - When the game asks a question (like a save file name), the answer skips the vocabulary check, since any name is allowed.
  - If Claude can't be reached, the transcript is sent as heard only if it passes the vocabulary check. The input field says why either way.

**Notes:**
- **Microphone permission:** the first time you press ⌥, macOS asks for microphone access. With `swift run`, the prompt names Terminal (or whichever app launched it). The built app asks for itself.
- **Accidental presses:** holds under 0.3 s are ignored, and so is silence, so it doesn't spend API calls. Pressing another key while holding ⌥ (to type a special character or use a shortcut) cancels the recording.
- **Why push-to-talk:** Fish's speech-to-text has no streaming endpoint. It transcribes one finished clip per request, so you have to mark when you're done talking.
- **Cost:** speech-to-text costs $0.36 per audio hour.
- **Cleanup model:** `claude-opus-5-5` at `effort: "low"`, with the instructions and vocabulary cached and JSON-schema output. Cleanup took about 2 s per command in testing. It adds a round trip on top of speech-to-text. For lower latency, construct `CommandInterpreter(apiKey:model:effort:serverSideFallbacks:)` with `model: "claude-haiku-4-5", effort: nil, serverSideFallbacks: false` in `PushToTalk`.
- **Live tests:** run the opt-in tests against the real APIs with `FISH_LIVE_TESTS=1 swift test --filter transcribesRealSpeech` and `ANTHROPIC_LIVE_TESTS=1 swift test --filter "interpretsRealSpeech|cleanedCommandsUseTheGamesWords"`.

## Voices: narrator, characters, and SNARK-9

Everything you hear goes through Fish Audio text-to-speech (`POST /v1/tts`, model `s2.1-pro-free`, raw PCM streamed with latency `balanced`), except sound effects. All voices share one speaker queue, so nobody talks over anybody. After each action you hear these parts, in order:

0. **Sound effects:** story moments play their sound before anything else.
   - When the Feinstein starts blowing up on Deck Nine ("A massive explosion rocks the ship", the `explosion` story event), a 6.5 s explosion plays first, and the narrator starts once it has died away.
   - The explosion is synthesized in code (`SoundEffect`): a main blast and two aftershocks as the hull gives way, each a crack plus a roar that darkens as it fades. Under them, a deep rumble sinks to 25 Hz and holds for several seconds, with debris crackling down for the first four. So there's no audio file or license, and it sounds the same every time.
   - **Red alert:** from that explosion on, an emergency siren whoops over a deep hull rumble and distant blasts.
     - It loops quietly under the voices: it fades in a second into the explosion, and ducks while push-to-talk is listening.
     - It stops when the danger is over: you escape in the pod and watch the Feinstein blow apart, you die, or the game restarts.
     - It's synthesized too (`RedAlert`), as a seamless 6 s loop.
   - To hear it, launch with `PLANETFALL_SEED=8` and `wait` nine times. Then `west` into the escape pod and `wait` three times to escape, or keep waiting to go down with the ship.

1. **Narrator:** Claude (`claude-opus-5-5`, effort `low`, streamed) retells what the game printed as a sentence or two about the surroundings and what changed.
   - Each sentence goes to Fish as soon as it's written. The first one is heard about 2 s after the text appears.
   - Character dialogue is removed first and replaced with markers like `[Blather speaks]`, so the narrator describes the scene ("Blather swaggers in, glaring at you") but never speaks anyone's lines.
   - Needs `ANTHROPIC_API_KEY`.
2. **Characters:** each named character speaks their own quoted lines in their voice.
   - The verb next to a quote becomes a Fish S2 delivery tag: "he sneers" adds `[sneering]`, "bellows" adds `[shouting]`, "Floyd giggles" adds `[laughing]`.
   - Finished character lines are cached in `~/Library/Caches/Planetfall/Voices`, so repeats play instantly and cost nothing.
3. **SNARK-9 (commentator):** the sidekick's Claude quip about your move, read in its own voice once it's written.

Sending a command, or starting push-to-talk, cuts everyone off, so the game never talks over you and the mic never hears it. Toggle each part from the Voices menu: Narrator (⇧⌘N), Character Voices (⇧⌘M), SNARK-9 Voice (⇧⌘J), Sound Effects (⇧⌘E). Errors appear in the command line's placeholder.

| Role | Fish voice | `.env` override |
|---|---|---|
| Narrator | "calm storyteller male" `e686ae649ee44f219a108aacba206c1a` | `FISH_VOICE_NARRATOR` |
| Ensign Blather | **arnold** `546972d2053c481d86fe4449a1b54e27` (cloned from `audio/arnold-soundboard-combined.mp3`) | `FISH_VOICE_BLATHER` |
| Floyd | "Energetic Child" `4fcb3a423c61415fb35604eba567d95f` | `FISH_VOICE_FLOYD` |
| Veldina | "Measured Storyteller" `8906b5268cae414fb9b8d3da6e84413d` | `FISH_VOICE_VELDINA` |
| Alien Ambassador | "IBM-7094" (monotone computer, for his translator) `50b20b6a22e04352877c0c01b194c1aa` | `FISH_VOICE_AMBASSADOR` |
| SNARK-9 | "Robot" `fe5b8eaa8b754a5b8d895265def9e5b2` | `FISH_VOICE_SIDEKICK` |

- **Arnold is an unlisted voice in Gaurav's Fish account.** Any Fish API key can use it by id (Fish's library doesn't list it), so it works for the whole team. The other voices are public, from Fish's voice library. To use a different Blather voice, set `FISH_VOICE_BLATHER`.
- **Finding character lines:** `DialogueExtractor` gives a quote to the nearest voiced name in its paragraph (`Blather shouts "…"`, `"…" bellows Blather`). Quotes near "labelled", "reads" or "embossed" are signs, so they stay with the narrator.
- **The ambassador is never quoted.** The game only reports what he says ("The ambassador asks where Admiral Smithers can be found."). Each of his reported lines and sounds maps to a line he speaks through his translator, e.g. "Where can Admiral Smithers be found?" or `[wheezing] Greetings, ensign.` The narrator gets `[Ambassador speaks]` in place of the report. These mappings are `reportedSpeech` in `VoiceCast.defaults`. To hear him, launch with `PLANETFALL_SEED=10` and `wait` five times: he arrives, speaks three lines, then says goodbye.
- **Adding a character:** add a `CharacterVoice` (id, the names the game uses for them, Fish voice id, and `reportedSpeech` if the game paraphrases them) to `VoiceCast.defaults`.
- **Why SNARK-9 isn't a Fish Agent:** Fish's hosted Agents can take text (`user.message` with `audio: true`). But they need the LiveKit WebRTC SDK, an agent configured in Fish's agent platform, and a session open for the whole game (Fish bills agents at $0.06/min). Their audio would also bypass the shared speaker queue. SNARK-9 already writes the commentary with Claude, so it gets a Fish voice instead.
- **Microphone:** push-to-talk records from the macOS default input (System Settings → Sound → Input), re-read on every press. Headphones that expose no microphone to macOS, like Bluetooth buds in headphone-only mode, can't be recorded from; the Mac's mic is used instead.
- **Live tests:** `FISH_LIVE_TESTS=1 swift test --filter streamsEveryCastVoice` and `ANTHROPIC_LIVE_TESTS=1 swift test --filter narratesARealTurn`.

## App icon

`Art/AppIcon.png` is the app icon: an original recruitment-poster-style painting of the player's ensign. Icons, and the square artwork they were made from, live in [Art/AppIcons/](Art/AppIcons/):

| Icon | Files | Use |
|---|---|---|
| Poster | `poster.png`, `poster-artwork.jpg` | Current icon |
| Ensign | `ensign.png`, `ensign-artwork.jpg` | Alternate; planned as an unlockable for landing on the planet (see [docs/achievements-plan.md](docs/achievements-plan.md)) |

To make an icon from new square artwork, shape it into a macOS icon (an 824-point rounded square on a 1024-point canvas, with a shadow), then copy it into place:

```sh
swift scripts/make-icon.swift Art/AppIcons/new-artwork.jpg Art/AppIcons/new.png
cp Art/AppIcons/new.png Art/AppIcon.png
```

`build-app.sh` turns `Art/AppIcon.png` into the app bundle's icon, and `swift run` uses it for the Dock icon.

## How it works

We don't port the game. `planetfall.z3` is Infocom's compiled game (Release 39), which runs on a Z-machine interpreter. The app runs **dfrotz** in the background and passes text in and out over pipes.

| Piece | File | Job |
|---|---|---|
| `FrotzOutputParser` | [Sources/PlanetfallEngine/FrotzOutputParser.swift](Sources/PlanetfallEngine/FrotzOutputParser.swift) | Splits dfrotz output into turns at the `>` prompt and pulls out the status line (room, score, moves). |
| `GameSession` | [Sources/PlanetfallEngine/GameSession.swift](Sources/PlanetfallEngine/GameSession.swift) | Owns the dfrotz process. Exposes observable state (`transcript`, `status`, `isAwaitingInput`) and an event stream. |
| `GameLocator` | [Sources/PlanetfallEngine/GameLocator.swift](Sources/PlanetfallEngine/GameLocator.swift) | Finds dfrotz and the story file. Override with `DFROTZ_PATH` / `PLANETFALL_STORY`. |
| `FishAPIKey`, `AnthropicAPIKey` | [Sources/PlanetfallEngine/FishAPIKey.swift](Sources/PlanetfallEngine/FishAPIKey.swift) | Load `FISH_API_KEY` / `ANTHROPIC_API_KEY` from the environment, then from `.env`. |
| `FishSpeechToText` | [Sources/PlanetfallEngine/FishSpeechToText.swift](Sources/PlanetfallEngine/FishSpeechToText.swift) | Uploads a WAV to Fish `POST /v1/asr` and returns a clean command (speaker markers and cues removed). |
| `SoundEffect` | [Sources/PlanetfallEngine/SoundEffect.swift](Sources/PlanetfallEngine/SoundEffect.swift) | Synthesizes story sound effects (the Deck Nine explosion) and picks the ones a turn's text triggers. |
| `RedAlert`, `LoopPlayer` | [Sources/PlanetfallEngine/RedAlert.swift](Sources/PlanetfallEngine/RedAlert.swift) | The siren-and-rumble loop that plays while the Feinstein is blowing up, and when it starts and stops. |
| `GameVocabulary` | [Sources/PlanetfallEngine/GameVocabulary.swift](Sources/PlanetfallEngine/GameVocabulary.swift) | Reads the parser's dictionary from the story file and checks that every word of a command is one the game knows. |
| `CommandInterpreter` | [Sources/PlanetfallEngine/CommandInterpreter.swift](Sources/PlanetfallEngine/CommandInterpreter.swift) | Sends what was heard, plus the current room and recent output (`GameSession.commandContext()`), to Claude and returns one parser command. |
| `VoiceCast`, `DialogueExtractor` | [Sources/PlanetfallEngine/CharacterVoice.swift](Sources/PlanetfallEngine/CharacterVoice.swift) | Which Fish voice each role uses, and splitting a turn into narration and character lines (with delivery tags). |
| `Narrator` | [Sources/PlanetfallEngine/Narrator.swift](Sources/PlanetfallEngine/Narrator.swift) | Streams Claude's spoken retelling of a turn, a sentence at a time. |
| `FishTextToSpeech`, `VoiceLineCache` | [Sources/PlanetfallEngine/FishTextToSpeech.swift](Sources/PlanetfallEngine/FishTextToSpeech.swift) | Streams a line from Fish `POST /v1/tts` as PCM, and caches finished lines on disk. |
| `VoiceDirector`, `PCMStreamPlayer` | [Sources/Planetfall/](Sources/Planetfall/) | Queues narrator, character, and SNARK-9 audio on one speaker, plays it as it streams, and stops on the next command or push-to-talk. |
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

### Art that changes with the story

Rooms can have alternate art for story moments, picked from **tags**:

- **Story events** come from the game's text. Each one starts at a trigger sentence and lasts until its end sentence (or a restart). The events are listed in [Sources/PlanetfallEngine/StoryEvent.swift](Sources/PlanetfallEngine/StoryEvent.swift).
- **Where you are** comes from dfrotz's object trace. While you're in the safety web, the `webbing` tag is on, however you got in or out.

| Tag | On when | Off when |
|---|---|---|
| `explosion` | "A massive explosion rocks the ship" | The pod clears the ship ("…you see the Feinstein dwindle…") |
| `planet` | "…a nearby planet swings into view through the port" | The pod lands ("The pod lands with a thud") |
| `webbing` | You're in the safety web | You leave the web |

For each room, the app tries `Art/Rooms/<room>-<tags>` with the active tags in the order they began, most specific first, then the plain room art:

| Moment | Tags | Art used |
|---|---|---|
| Deck Nine after the first explosion | explosion | `deck-nine-explosion.jpg` |
| In the webbing while the ship is exploding | explosion, webbing | `escape-pod-explosion-webbing.jpg` |
| In the webbing after launch | webbing | `escape-pod-webbing.jpg` |
| In the webbing, approaching the planet | planet, webbing | `escape-pod-planet-webbing.jpg` |
| Out of the webbing | none | `escape-pod.jpg` |

Changing art takes no code: name the image for the room plus its tags. Tags reset when the game restarts, including RESTART typed in the game. One limitation: RESTORE doesn't reset them.

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

The opening is random: on Deck Nine, the game sends Blather, the alien ambassador, or nobody. Pass `randomSeed:` to `GameSession`, or set `PLANETFALL_SEED` when launching the app, to get the same game every time. For example, with seed 8, Blather arrives on turn 4: `PLANETFALL_SEED=8 swift run Planetfall`, or `open --env PLANETFALL_SEED=8 build/Planetfall.app`. With seed 10, the alien ambassador arrives on turn 1.

## Sidekick commentary

**SNARK-9**, a jaded retro-gaming commentary robot, co-hosts your playthrough like a let's-play sidekick. It isn't part of the game: it watches you play from outside, the way a viewer would, and can't be seen or talked to in Planetfall. After each turn, the app sends the recent game output to Claude (`claude-opus-5-5`, low effort, streamed). SNARK-9's reaction types out live in a bar above the command line. It passes on routine turns, so it doesn't comment on everything.

- **Setup:** it needs `ANTHROPIC_API_KEY` in `.env`. Without a key, the bar is hidden.
- **Turning it off:** use **Sidekick → SNARK-9 Commentary** (⇧⌘K). The setting is remembered between launches.
- **Recasting the sidekick:** edit `SidekickPersona.default` in [Sources/PlanetfallEngine/Commentator.swift](Sources/PlanetfallEngine/Commentator.swift) to change the name, description and personality. The rules (short, no spoilers, PG-13, no invented events) are in the system prompt in the same file.
- **Avatar:** a square image at `Art/NPCs/sidekick.jpg`, shown at 80 points beside the quip. Click it to see it close up, like character portraits. Without the image, the bar shows an icon.
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
