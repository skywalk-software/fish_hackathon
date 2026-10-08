import Foundation
import Observation

/// The let's-play sidekick: watches the game and streams a quip from Claude after the
/// player's turns. Observe `line` for the caption; add a handler with `onLineFinished` to
/// speak it (e.g. Fish TTS in the sidekick's own voice).
@MainActor
@Observable
public final class Sidekick {
    public let persona: SidekickPersona
    /// The current quip, growing as it streams in. Empty until the first one.
    public private(set) var line = ""
    /// True from sending a turn to Claude until its quip finishes (or it passes).
    public private(set) var isThinking = false
    /// The last error, shown in place of a quip; cleared by the next successful one.
    public private(set) var errorMessage: String?
    /// Turn commentary on or off. Remembered between launches.
    public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { cancel() }
        }
    }

    @ObservationIgnored private let commentator: Commentator
    @ObservationIgnored private weak var session: GameSession?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// A turn arrived while a quip was still streaming; comment on the latest state afterwards.
    @ObservationIgnored private var hasPendingTurn = false
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
            case .command, .ended:
                break
            }
        }
    }

    /// Called with each complete quip (not passes or errors).
    public func onLineFinished(_ handler: @escaping (String) -> Void) {
        finishedHandlers.append(handler)
    }

    private func turnFinished() {
        guard isEnabled else { return }
        if task != nil {
            hasPendingTurn = true
        } else {
            comment()
        }
    }

    private func comment() {
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
        hasPendingTurn = false
        isThinking = true
        task = Task { [weak self, commentator] in
            var text = ""
            var failure: Error?
            do {
                for try await delta in commentator.commentary(on: context) {
                    if text.isEmpty { self?.line = "" }
                    text += delta
                    // The caption hides delivery tags; the voice gets them (onLineFinished).
                    self?.line = DeliveryTags.strip(text)
                }
            } catch is CancellationError {
                return
            } catch {
                failure = error
            }
            self?.finished(text: text.trimmingCharacters(in: .whitespacesAndNewlines), failure: failure)
        }
    }

    private func finished(text: String, failure: Error?) {
        task = nil
        isThinking = false
        if let failure, !Task.isCancelled {
            // A refusal just means no quip this turn; only surface real failures.
            if case CommandInterpreterError.refused = failure {} else {
                errorMessage = failure.localizedDescription
            }
        } else if !text.isEmpty {
            errorMessage = nil
            previousLines.append(DeliveryTags.strip(text))
            previousLines = previousLines.suffix(Self.maxPreviousLines)
            for handler in finishedHandlers { handler(text) }
        }
        if hasPendingTurn && isEnabled { comment() }
    }

    private func cancel() {
        task?.cancel()
        task = nil
        hasPendingTurn = false
        pendingAwards = []
        isThinking = false
    }

    /// Forget the previous game's jokes (e.g. after a restart).
    public func reset() {
        cancel()
        line = ""
        errorMessage = nil
        previousLines = []
    }
}
