import Foundation
import Observation

/// Everything the game session reports. Subscribe with `GameSession.addObserver`
/// to hook in other features (e.g. speak each `.turn` aloud).
public enum GameEvent: Sendable {
    /// The game finished printing and is waiting for input.
    case turn(GameTurn)
    /// The player (or voice input) sent a line to the game.
    case command(String)
    /// The dfrotz process exited.
    case ended(exitCode: Int32)
    /// The player earned an achievement. Sent just before the `.turn` it happened in, so
    /// observers (like the sidekick) know about it when they handle that turn.
    case achievementUnlocked(Achievement)
}

public enum TranscriptEntry: Identifiable, Equatable, Sendable {
    case narration(id: Int, text: String)
    case command(id: Int, text: String)
    case system(id: Int, text: String)

    public var id: Int {
        switch self {
        case .narration(let id, _), .command(let id, _), .system(let id, _): id
        }
    }
}

public enum GameSessionError: LocalizedError {
    case dfrotzNotFound
    case storyNotFound

    public var errorDescription: String? {
        switch self {
        case .dfrotzNotFound:
            "Couldn't find dfrotz. Install it with `brew install frotz`, or set DFROTZ_PATH."
        case .storyNotFound:
            "Couldn't find planetfall.z3. Run scripts/fetch-story.sh, or set PLANETFALL_STORY."
        }
    }
}

/// Runs Planetfall inside dfrotz (Frotz's plain-text interface) and exposes it as
/// observable state plus a stream of events.
@MainActor
@Observable
public final class GameSession {
    public private(set) var transcript: [TranscriptEntry] = []
    public private(set) var status: StatusLine?
    public private(set) var isAwaitingInput = false
    /// Whether the player has plugged their ears (see `EarPlugs`), silencing the siren.
    public private(set) var earsPlugged = false
    /// True while a cheat is replaying its script (see `Cheat`): input is locked.
    public var isRunningCheat: Bool { cheatRun != nil }
    /// True while a `Nap` is running: the app is sending hidden WAITs, so input is locked.
    public var isNapping: Bool { nap != nil }
    /// What the game is waiting for: a command at `>`, or an answer to a question such as a
    /// save file name.
    public private(set) var prompt: GameTurn.Prompt = .command
    public private(set) var isRunning = false
    /// Where each character is (character id -> room name), tracked from dfrotz's
    /// object-movement trace. Characters not yet seen or removed from play are absent.
    public private(set) var characterLocations: [String: String] = [:]
    /// Where earned achievements are recorded; nil to not track them.
    @ObservationIgnored public var achievements: AchievementStore?
    /// Ids of the active `StoryEvent`s, oldest first.
    public private(set) var storyEvents: [String] = []
    /// The object the player is inside, from the object trace (e.g. "safety web"), or the
    /// room name when they're just standing in a room. Nil until the game reports a move.
    public private(set) var playerHolder: String?

    /// Tags that pick story-specific art, oldest first: active story events, then where the
    /// player is (in the safety web: "webbing"). Rooms look for
    /// Art/Rooms/<room>-<tags>.jpg, most specific first.
    public var artTags: [String] {
        // While asleep, the room looks as it did when the player dozed off: the hidden turns
        // mustn't give away what wakes them.
        if let nap { return nap.shownArtTags }
        return storyEvents + (playerHolder.flatMap { StoryEvent.holderTags[$0] }.map { [$0] } ?? [])
    }

    /// Characters in the same room as the player, in `GameCharacter.all` order.
    public var presentCharacters: [GameCharacter] {
        if let nap { return nap.shownCharacters }
        return actuallyPresentCharacters
    }

    /// Who is really in the room, even mid-nap.
    private var actuallyPresentCharacters: [GameCharacter] {
        guard let here = status?.location else { return [] }
        return GameCharacter.all.filter { characterLocations[$0.id] == here }
    }

    private let dfrotzURL: URL
    private let storyURL: URL
    private let savesDirectory: URL
    /// Fixed by the initializer, or by a cheat (which replays with `Cheat.seed`).
    private var randomSeed: Int?
    /// The initializer's seed, which a normal restart goes back to.
    private let initialSeed: Int?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stdin: FileHandle?
    /// The nap in progress, if any (see `Nap`). Observed, so `isNapping` updates the UI.
    private var nap: NapState?
    /// The cheat being replayed, if any. Observed, so `isRunningCheat` updates the UI.
    private var cheatRun: CheatRun?

    private struct CheatRun {
        let cheat: Cheat
        var steps: [Cheat.Step]
        /// The game has printed its opening, so the script can start.
        var started = false
        /// While waiting for text: the text, how many WAITs so far, and the limit.
        var waitingFor: (text: String, waits: Int, max: Int)?
    }

    private struct NapState {
        /// What the screen showed when the player fell asleep, kept until they wake.
        var shownArtTags: [String]
        var shownCharacters: [GameCharacter]
        var id = UUID()
        var started = ContinuousClock.now
        var turns = 0
        var blatherVisited = false
        /// Set once something woke the player, while the wake-up turn waits to be shown.
        var waking = false
    }

    /// The shortest a nap appears to last (it really takes a fraction of a second), so the
    /// player sees "Sleeping…" and the room darken.
    @ObservationIgnored public var napMinimumDuration: Duration = .seconds(2)
    /// Extra time before the ambassador wakes the player (the explosion wakes them instantly).
    @ObservationIgnored public var napAmbassadorDelay: Duration = .seconds(1)
    /// Before an explosion wake-up, portraits clear this long ahead of it (they slide out in
    /// about 0.35 s).
    static let napPortraitClearLead: Duration = .milliseconds(500)
    /// What ended the most recent nap, for the wake-up presentation.
    public private(set) var lastWakeReason: Nap.WakeReason?
    @ObservationIgnored private var stdout: FileHandle?
    @ObservationIgnored private var parser = FrotzOutputParser()
    @ObservationIgnored private var observers: [(GameEvent) -> Void] = []
    @ObservationIgnored private var nextEntryID = 0
    @ObservationIgnored private var outputGeneration = 0

    /// How long output must be quiet before we treat it as a non-`>` prompt.
    private static let questionQuietPeriod: Duration = .milliseconds(300)

    /// `randomSeed` makes the game's random events repeat exactly (useful for tests and
    /// demos); nil plays a different game each time.
    public init(dfrotzURL: URL, storyURL: URL, savesDirectory: URL, randomSeed: Int? = nil) {
        self.dfrotzURL = dfrotzURL
        self.storyURL = storyURL
        self.savesDirectory = savesDirectory
        self.randomSeed = randomSeed
        self.initialSeed = randomSeed
    }

    /// Finds dfrotz and the story file in their usual places.
    public static func makeDefault() throws -> GameSession {
        guard let dfrotz = GameLocator.dfrotzURL() else { throw GameSessionError.dfrotzNotFound }
        guard let story = GameLocator.storyURL() else { throw GameSessionError.storyNotFound }
        // PLANETFALL_SEED replays the same game, e.g. 8 to have Blather show up on turn 4.
        let seed = ProcessInfo.processInfo.environment["PLANETFALL_SEED"].flatMap { Int($0) }
        return GameSession(dfrotzURL: dfrotz, storyURL: story, savesDirectory: GameLocator.savesDirectory(),
                           randomSeed: seed)
    }

    /// Calls `handler` on the main actor for every event. Keep handlers quick;
    /// start a Task for slow work like network TTS.
    public func addObserver(_ handler: @escaping (GameEvent) -> Void) {
        observers.append(handler)
    }

    public func start() throws {
        guard process == nil else { return }
        try FileManager.default.createDirectory(at: savesDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = dfrotzURL
        // -q quiet startup, -m no MORE prompts, -p plain ASCII, -w wide so the
        // game rarely hard-wraps (the UI wraps instead), -o trace object movement
        // so we know where characters are.
        var arguments = ["-q", "-m", "-p", "-o", "-w", "255"]
        if let randomSeed { arguments += ["-s", String(randomSeed)] }
        process.arguments = arguments + [storyURL.path]
        // Save files land here because the game asks for a bare filename.
        process.currentDirectoryURL = savesDirectory

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.receive(text) }
        }
        process.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            Task { @MainActor in self?.processEnded(exitCode: code) }
        }

        try process.run()
        self.process = process
        self.stdin = input.fileHandleForWriting
        self.stdout = output.fileHandleForReading
        isRunning = true
    }

    /// Sends one line of input to the game.
    public func send(_ line: String) {
        guard isRunning, let stdin, nap == nil, cheatRun == nil else { return }
        let line = line.replacingOccurrences(of: "\n", with: " ")
        append(.command(id: takeID(), text: line))
        if let request = Cheat.request(in: line) {
            emit(.command(line))
            switch request {
            case .unknown(let name):
                let text = name.isEmpty
                    ? "Cheats: \(Cheat.list)."
                    : "There's no cheat called \"\(name)\". Try \(Cheat.list)."
                publish(GameTurn(text: text, status: status, prompt: .command))
            case .cheat(let cheat):
                startCheat(cheat)
            }
            return
        }
        if let earCommand = EarPlugs.command(in: line) {
            // Handled by the app, not the game: no game time passes.
            emit(.command(line))
            let response = EarPlugs.response(to: earCommand, wasPlugged: earsPlugged)
            earsPlugged = earCommand == .plug
            publish(GameTurn(text: response, status: status, prompt: .command))
            return
        }
        isAwaitingInput = false
        if Nap.isNapCommand(line),
           Nap.applies(location: status?.location, storyEvents: storyEvents, playerHolder: playerHolder) {
            // Our SLEEP instead of the game's: wait, unseen, until something wakes the player.
            nap = NapState(shownArtTags: artTags, shownCharacters: presentCharacters)
            stdin.write(Data("wait\n".utf8))
        } else {
            stdin.write(Data((line + "\n").utf8))
        }
        emit(.command(line))
    }

    public func stop() {
        process?.terminate()
    }

    /// Stops the current game and starts a fresh one.
    public func restart() throws {
        cheatRun = nil
        randomSeed = initialSeed
        try restartProcess(keepingTranscript: false)
    }

    /// Replaces the dfrotz process with a fresh game and forgets everything learned from the
    /// old one.
    private func restartProcess(keepingTranscript: Bool) throws {
        // Detach the old process first so its last output and exit don't reach the new game.
        stdout?.readabilityHandler = nil
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        stdin = nil
        stdout = nil
        parser = FrotzOutputParser()
        if !keepingTranscript { transcript = [] }
        status = nil
        characterLocations = [:]
        storyEvents = []
        playerHolder = nil
        nap = nil
        earsPlugged = false
        isAwaitingInput = false
        prompt = .command
        isRunning = false
        try start()
    }

    // MARK: - Output handling

    private func receive(_ chunk: String) {
        for turn in parser.consume(chunk) {
            deliver(turn)
        }
        // A prompt without `>` (like the save filename) never completes a turn,
        // so if output stops mid-buffer for a moment, treat it as a question.
        outputGeneration += 1
        guard parser.hasPendingOutput else { return }
        let generation = outputGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.questionQuietPeriod)
            guard let self, self.outputGeneration == generation,
                  let turn = self.parser.flushPending() else { return }
            self.deliver(turn)
        }
    }

    private func deliver(_ turn: GameTurn) {
        if cheatRun != nil {
            cheatTurn(turn)
            return
        }
        if nap != nil {
            napTurn(turn)
            return
        }
        applyState(from: turn)
        publish(turn)
    }

    /// Restarts the game with the cheat seed and starts replaying the cheat's script.
    private func startCheat(_ cheat: Cheat) {
        randomSeed = Cheat.seed
        cheatRun = CheatRun(cheat: cheat, steps: cheat.steps)
        do {
            try restartProcess(keepingTranscript: true)
        } catch {
            cheatRun = nil
            append(.system(id: takeID(), text: "The cheat couldn't restart the game: \(error.localizedDescription)"))
        }
    }

    /// One hidden turn of a cheat's replay: track the game's state, show nothing, and send the
    /// script's next command. After the last one, shows that turn as where the cheat landed.
    private func cheatTurn(_ turn: GameTurn) {
        guard var run = cheatRun else { return }
        applyState(from: turn)
        if run.started, let waiting = run.waitingFor {
            if !turn.text.contains(waiting.text), waiting.waits < waiting.max, turn.prompt == .command {
                run.waitingFor = (waiting.text, waiting.waits + 1, waiting.max)
                cheatRun = run
                stdin?.write(Data("wait\n".utf8))
                return
            }
            run.waitingFor = nil
        }
        run.started = true
        if turn.prompt == .command, !run.steps.isEmpty {
            switch run.steps.removeFirst() {
            case .send(let command):
                stdin?.write(Data((command + "\n").utf8))
            case .waitUntil(let text, let max):
                run.waitingFor = (text, 1, max)
                stdin?.write(Data("wait\n".utf8))
            }
            cheatRun = run
            return
        }
        // Done (or the game asked something unexpected): land here.
        cheatRun = nil
        append(.system(id: takeID(), text: "Cheat: \(run.cheat.rawValue). \(run.cheat.summary)"))
        var landing = turn
        landing.objectEvents = []  // already applied
        landing.isCheat = true
        publish(landing)
    }

    /// One hidden turn of a nap: track the game's state, but show and emit nothing (so no
    /// commentary or voices run). Ends the nap with a single combined turn when something
    /// wakes the player, otherwise sends the next WAIT.
    private func napTurn(_ turn: GameTurn) {
        guard var state = nap, !state.waking else { return }
        applyState(from: turn)
        state.turns += 1
        state.blatherVisited = state.blatherVisited || Nap.blatherVisited(in: turn)
        if let reason = Nap.wakeReason(for: turn, napTurns: state.turns) {
            var woken = turn
            woken.text = Nap.wakeText(final: turn, reason: reason, blatherVisited: state.blatherVisited)
            woken.objectEvents = []  // already applied above
            // Show the wake-up once the nap has visibly lasted its minimum, plus a beat for the
            // ambassador's wheezing; the explosion wakes the player the moment that's up.
            state.waking = true
            nap = state
            let elapsed = ContinuousClock.now - state.started
            var delay = napMinimumDuration > elapsed ? napMinimumDuration - elapsed : .zero
            if reason == .ambassador { delay += napAmbassadorDelay }
            let napID = state.id
            Task { [weak self] in
                if reason == .explosion {
                    // Clear anyone who left (or was swept away) while it's still dark, so no
                    // portrait lingers over the explosion when the player snaps awake.
                    let clearing = Self.napPortraitClearLead
                    try? await Task.sleep(for: delay > clearing ? delay - clearing : .zero)
                    guard let self, self.nap?.id == napID else { return }
                    self.nap?.shownCharacters = self.actuallyPresentCharacters
                    try? await Task.sleep(for: delay > clearing ? clearing : delay)
                } else {
                    try? await Task.sleep(for: delay)
                }
                // A restart (or the game ending) during the wait cancels the wake-up.
                guard let self, self.nap?.id == napID else { return }
                self.lastWakeReason = reason
                self.nap = nil
                self.publish(woken)
            }
        } else {
            nap = state
            stdin?.write(Data("wait\n".utf8))
        }
    }

    /// Updates what the session knows about the game from a turn's output.
    private func applyState(from turn: GameTurn) {
        // A fresh game (including RESTART typed in the game) starts over: forget where
        // characters were and which story events happened.
        if turn.text.contains(StoryEvent.gameStartMarker) {
            characterLocations = [:]
            storyEvents = []
            playerHolder = nil
            earsPlugged = false
        }
        for event in turn.objectEvents {
            GameCharacter.apply(event, to: &characterLocations)
            if case .moved(let args) = event, args.hasPrefix("player ") {
                playerHolder = String(args.dropFirst("player ".count))
            }
        }
        StoryEvent.update(&storyEvents, with: turn.text)
        if let newStatus = turn.status { status = newStatus }
    }

    /// Shows a turn to the player and everything observing the session.
    private func publish(_ turn: GameTurn) {
        if !turn.text.isEmpty { append(.narration(id: takeID(), text: turn.text)) }
        isAwaitingInput = true
        prompt = turn.prompt
        // A cheat's landing doesn't earn achievements (though anything played after it does).
        for achievement in turn.isCheat ? [] : achievements?.record(turn.text) ?? [] {
            emit(.achievementUnlocked(achievement))
        }
        emit(.turn(turn))
    }

    private func processEnded(exitCode: Int32) {
        nap = nil
        cheatRun = nil
        if let turn = parser.flushPending() {
            if let newStatus = turn.status { status = newStatus }
            if !turn.text.isEmpty { append(.narration(id: takeID(), text: turn.text)) }
        }
        process = nil
        stdin = nil
        stdout = nil
        isRunning = false
        isAwaitingInput = false
        append(.system(id: takeID(), text: "The game has ended."))
        emit(.ended(exitCode: exitCode))
    }

    private func append(_ entry: TranscriptEntry) {
        transcript.append(entry)
    }

    private func takeID() -> Int {
        defer { nextEntryID += 1 }
        return nextEntryID
    }

    private func emit(_ event: GameEvent) {
        for observer in observers { observer(event) }
    }
}
