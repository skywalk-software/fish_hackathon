import Foundation
import Observation

/// The let's-play sidekick: watches the game and streams a quip from Claude after the
/// player's turns. Observe `line` for the caption; add a handler with `onLineFinished` to
/// speak it (e.g. Fish TTS in the sidekick's own voice).
@MainActor
@Observable
public final class Sidekick {
    public let persona: SidekickPersona
    /// The caption: the quip being spoken (or, with no voice, as it streams in). Blank while
    /// SNARK-9 is waiting, thinking, or passing, and from the moment the player sends a command.
    public private(set) var line = ""
    /// True while Claude is writing a quip.
    public private(set) var isThinking = false
    /// The last error, shown in place of a quip; cleared by the next successful one.
    public private(set) var errorMessage: String?
    /// Turn commentary on or off. Remembered between launches.
    public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled {
                cancel(keepingAwards: false)
                line = ""
            }
        }
    }
    /// How long after a turn to wait before asking Claude, so quick successive commands don't
    /// each cost a request (every command cancels the wait).
    public var commentDelay: Duration = .seconds(2)
    /// Also awaited before asking Claude: the voices set it to wait until the turn's narration
    /// is nearly over, so the quip is written just in time to follow it.
    @ObservationIgnored public var readyToComment: (@MainActor () async -> Void)?
    /// When true, a finished quip's caption stays hidden until `revealCaption()` (called as its
    /// voice starts), so it appears when SNARK-9 actually speaks.
    @ObservationIgnored public var captionWaitsForVoice = false

    @ObservationIgnored private let commentator: Commentator
    @ObservationIgnored private weak var session: GameSession?
    /// Waiting for the right moment, then streaming a quip.
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pendingCaption: String?
    @ObservationIgnored private var previousLines: [String] = []
    /// Achievements earned since the last quip was requested, to be awarded in the next one.
    @ObservationIgnored private var pendingAwards: [Achievement] = []
    @ObservationIgnored private var finishedHandlers: [(String) -> Void] = []

    private static let enabledKey = "sidekickEnabled"
    private static let maxPreviousLines = 8

    /// Nil when there's no Anthropic API key.
    public static func makeDefault(session: GameSession) -> Sidekick? {
        AnthropicAPIKey.load().map { Sidekick(session: session, commentator: Commentator(apiKey: $0)) }
    }

    public init(session: GameSession, commentator: Commentator) {
        self.session = session
        self.commentator = commentator
        self.persona = commentator.persona
        self.isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        session.addObserver { [weak self] event in
            guard let self else { return }
            switch event {
            case .achievementUnlocked(let achievement):
                // Arrives just before its turn, so the next quip can award it.
                if self.isEnabled { self.pendingAwards.append(achievement) }
            case .turn(let turn):
                // Skip mid-command questions like the save filename prompt.
                guard turn.prompt == .command else { return }
                self.turnFinished()
            case .command:
                // The player moved on: drop any quip in progress and clear the caption.
                self.cancel(keepingAwards: true)
                self.line = ""
            case .ended:
                self.cancel(keepingAwards: false)
                self.line = ""
            }
        }
    }

    /// Called with each complete quip (not passes or errors), delivery tags included.
    public func onLineFinished(_ handler: @escaping (String) -> Void) {
        finishedHandlers.append(handler)
    }

    /// Shows the finished quip's caption; the voices call this as SNARK-9 starts speaking it.
    public func revealCaption() {
        guard let pendingCaption else { return }
        line = pendingCaption
        self.pendingCaption = nil
    }

    /// Hides the caption (the player skipped SNARK-9's line).
    public func dismissCaption() {
        line = ""
        pendingCaption = nil
    }

    private func turnFinished() {
        guard isEnabled else { return }
        task?.cancel()
        task = Task { [weak self] in
            guard let delay = self?.commentDelay else { return }
            do { try await Task.sleep(for: delay) } catch { return }
            if let ready = self?.readyToComment { await ready() }
            guard !Task.isCancelled else { return }
            await self?.comment()
        }
    }

    /// Asks Claude for a quip about the game as it is now. Runs inside `task`.
    private func comment() async {
        guard let session else { return }
        let context = CommentaryContext(
            location: session.status?.location,
            score: session.status?.score,
            moves: session.status?.moves,
            turnsPlayed: session.transcript.filter { if case .command = $0 { true } else { false } }.count,
            recentOutput: CommandContext.recent(session.transcript, location: nil).recentOutput,
            previousLines: previousLines,
            newAchievements: pendingAwards)
        pendingAwards = []
        isThinking = true
        var text = ""
        var failure: Error?
        do {
            for try await delta in commentator.commentary(on: context) {
                text += delta
                // With no voice to wait for, the caption types in as Claude writes it.
                if !captionWaitsForVoice { line = DeliveryTags.strip(text) }
            }
        } catch {
            failure = error
        }
        isThinking = false
        guard !Task.isCancelled, !(failure is CancellationError) else {
            // Cut off by a new command: award these with the next quip instead.
            pendingAwards = context.newAchievements + pendingAwards
            return
        }
        task = nil
        finished(text: text.trimmingCharacters(in: .whitespacesAndNewlines), failure: failure)
    }

    private func finished(text: String, failure: Error?) {
        if let failure {
            // A refusal just means no quip this turn; only surface real failures.
            if case CommandInterpreterError.refused = failure {} else {
                errorMessage = failure.localizedDescription
            }
            line = ""
        } else if text.isEmpty {
            line = ""  // SNARK-9 passed on this turn.
        } else {
            errorMessage = nil
            let caption = DeliveryTags.strip(text)
            previousLines.append(caption)
            previousLines = previousLines.suffix(Self.maxPreviousLines)
            if captionWaitsForVoice {
                pendingCaption = caption
            } else {
                line = caption
            }
            for handler in finishedHandlers { handler(text) }
        }
    }

    private func cancel(keepingAwards: Bool) {
        task?.cancel()
        task = nil
        pendingCaption = nil
        isThinking = false
        if !keepingAwards { pendingAwards = [] }
    }

    /// Forget the previous game's jokes (e.g. after a restart).
    public func reset() {
        cancel(keepingAwards: false)
        line = ""
        errorMessage = nil
        previousLines = []
    }
}
