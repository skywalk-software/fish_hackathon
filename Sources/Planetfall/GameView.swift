import PlanetfallEngine
import SwiftUI

struct GameView: View {
    let session: GameSession
    var sidekick: Sidekick?
    var voices: VoiceDirector?
    var achievements: AchievementStore?

    @State private var input = ""
    @State private var history: [String] = []
    @State private var historyIndex: Int?
    @State private var pushToTalk = PushToTalk()
    /// A spoken command waiting in the command box to be sent; cleared if the player edits it.
    @State private var pendingVoiceCommand: String?
    /// The portrait shown full-window, if any: a character in the room or the sidekick.
    @State private var closeup: Portrait?
    /// The achievement banner currently showing, if any.
    @State private var toast: Achievement?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            StatusBar(status: session.status)
            VStack(spacing: 0) {
                RoomArtView(location: session.status?.location, artTags: session.artTags)
                    // Sleeping darkens the room over the nap. The explosion snaps it back
                    // instantly; the ambassador's wheezing fades it back in.
                    .overlay {
                        Color.black
                            .opacity(session.isNapping ? 0.85 : 0)
                            .allowsHitTesting(false)
                            .animation(napDimAnimation, value: session.isNapping)
                    }
                Divider()
                TranscriptTextView(entries: session.transcript)
            }
            // Characters in the room appear as portraits over the top corner, so room
            // art never has to be drawn with and without each character.
            .overlay(alignment: .topTrailing) {
                CharacterInsets(characters: session.presentCharacters) { character in
                    closeup = Portrait(artID: character.id, name: character.name)
                }
            }
            // New achievements, top-left so they don't cover character portraits.
            .overlay(alignment: .topLeading) {
                if let toast {
                    AchievementToast(achievement: toast) { self.toast = nil }
                        .padding(16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.4), value: toast)
            if let sidekick, sidekick.isEnabled {
                Divider()
                SidekickBar(sidekick: sidekick) {
                    closeup = Portrait(artID: sidekick.persona.artID, name: sidekick.persona.name)
                }
            }
            Divider()
            inputBar
        }
        .background(Theme.background)
        .overlay {
            if let closeup, let image = Artwork.character(closeup.artID) {
                CharacterCloseup(name: closeup.name, image: image) { self.closeup = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: closeup)
        .onChange(of: achievements?.latestUnlock) { _, unlocked in
            guard let unlocked else { return }
            toast = unlocked
            Task {
                try? await Task.sleep(for: Self.toastDuration)
                if toast == unlocked { toast = nil }
            }
        }
        .onAppear {
            inputFocused = true
            pushToTalk.activate(canListen: { session.isRunning && !session.isNapping && !session.isRunningCheat }, context: { session.commandContext() },
                                onCommand: sendVoiceCommand)
        }
        .onDisappear { pushToTalk.deactivate() }
        // Don't let the microphone hear the game talking.
        .onChange(of: pushToTalk.phase) { _, phase in
            if phase == .listening { voices?.stop() }
            voices?.setListening(phase == .listening)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text(">")
                .foregroundStyle(Theme.accent)
            // The placeholder is drawn by us rather than the text field: while the field has
            // focus, macOS draws its own placeholder in the system color, which in Light Mode
            // is nearly black and invisible on this background.
            TextField("", text: $input)
                .textFieldStyle(.plain)
                .background(alignment: .leading) {
                    if input.isEmpty {
                        Text(verbatim: placeholder)
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                }
                .focused($inputFocused)
                .disabled(!session.isRunning || session.isNapping || session.isRunningCheat)
                .onSubmit(submit)
                .onKeyPress(.space) {
                    // Space on an empty line skips whoever is talking (if anyone is); otherwise
                    // it's just a space.
                    guard input.isEmpty, voices?.skipSpeaker() == true else { return .ignored }
                    return .handled
                }
                .onKeyPress(.escape) {
                    // Stop a spoken command from sending itself, leaving it to edit.
                    guard pendingVoiceCommand != nil else { return .ignored }
                    pendingVoiceCommand = nil
                    return .handled
                }
                .onKeyPress(.upArrow) { recallHistory(-1) }
                .onKeyPress(.downArrow) { recallHistory(1) }
            MicButton(pushToTalk: pushToTalk)
                .disabled(!session.isRunning || pushToTalk.unavailableReason != nil)
        }
        .font(Theme.font)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(InvertedFieldSelection())
    }

    private var placeholder: String {
        guard session.isRunning else { return "The game has ended" }
        if session.isNapping { return "Sleeping…" }
        if session.isRunningCheat { return "Cheating…" }
        switch pushToTalk.phase {
        case .listening: return "Listening… release to send"
        case .transcribing: return "Transcribing…"
        case .interpreting: return pushToTalk.heard.map { "Interpreting “\($0)”…" } ?? "Interpreting…"
        case .idle:
            return pushToTalk.notice ?? voices?.errorMessage
                ?? (pushToTalk.unavailableReason == nil ? "What next? (hold ⌥ to speak)" : "What next?")
        }
    }

    private var napDimAnimation: Animation? {
        if session.isNapping { return .easeIn(duration: 2) }
        return session.lastWakeReason == .explosion ? nil : .easeOut(duration: 0.8)
    }

    /// How long an achievement banner stays up (it can be clicked away sooner).
    private static let toastDuration: Duration = .seconds(8)

    /// How long a spoken command sits in the command box before it's sent.
    private static let voiceCommandPreview: Duration = .milliseconds(800)

    /// Shows a spoken command in the command box, then sends it. Typing (or pressing Escape)
    /// during the pause cancels the automatic send so the player can fix it first.
    private func sendVoiceCommand(_ command: String) {
        input = command
        historyIndex = nil
        pendingVoiceCommand = command
        Task {
            try? await Task.sleep(for: Self.voiceCommandPreview)
            guard pendingVoiceCommand == command, input == command else { return }
            pendingVoiceCommand = nil
            submit()
        }
    }

    private func submit() {
        pendingVoiceCommand = nil
        let command = input.trimmingCharacters(in: .whitespaces)
        // Empty input is allowed: some prompts (e.g. the save filename) accept the default.
        session.send(command)
        if !command.isEmpty { history.append(command) }
        historyIndex = nil
        input = ""
        inputFocused = true
    }

    private func recallHistory(_ step: Int) -> KeyPress.Result {
        guard !history.isEmpty else { return .ignored }
        let next = (historyIndex ?? history.count) + step
        if next >= history.count {
            historyIndex = nil
            input = ""
        } else {
            historyIndex = max(0, next)
            input = history[historyIndex!]
        }
        return .handled
    }
}

/// Hold to talk, same as holding ⌥.
private struct MicButton: View {
    let pushToTalk: PushToTalk
    @State private var pressing = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            switch pushToTalk.phase {
            case .listening:
                Image(systemName: "mic.fill").foregroundStyle(Theme.accent)
            case .transcribing, .interpreting:
                ProgressView().controlSize(.small)
            case .idle:
                Image(systemName: "mic").foregroundStyle(isEnabled ? Theme.text : Theme.dim.opacity(0.5))
            }
        }
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled, !pressing else { return }
                    pressing = true
                    pushToTalk.begin()
                }
                .onEnded { _ in
                    pressing = false
                    pushToTalk.end()
                }
        )
        .help(pushToTalk.unavailableReason ?? "Hold to speak a command (or hold ⌥)")
        .accessibilityLabel("Push to talk")
    }
}

private struct StatusBar: View {
    let status: StatusLine?

    var body: some View {
        HStack {
            Text(status?.location ?? "Planetfall")
                .fontWeight(.semibold)
            Spacer()
            if let status {
                Text(verbatim: "Score \(status.score)")
                Text(verbatim: "Moves \(status.moves)")
                    .padding(.leading, 12)
            }
        }
        .font(Theme.font)
        .foregroundStyle(Theme.background)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.accent)
    }
}

/// The current room's illustration, if we have one. Crossfades when you change rooms
/// and collapses entirely in rooms without art.
private struct RoomArtView: View {
    let location: String?
    let artTags: [String]

    var body: some View {
        let art = location.flatMap { Artwork.room($0, tags: artTags) }
        let image = art?.image
        // A fixed-size box with the image as an overlay, so the fill-scaled image
        // gets clipped to the box instead of growing the layout.
        Color.clear
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical) { height, _ in image == nil ? 0 : height * 0.45 }
            .overlay {
                if let image, let location {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .accessibilityLabel(location)
                        // Keyed by the art shown, so a story event crossfades the room too.
                        .id(art?.slug)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                // Fade the bottom edge into the transcript background.
                if image != nil {
                    LinearGradient(colors: [.clear, Theme.background], startPoint: .top, endPoint: .bottom)
                        .frame(height: 48)
                }
            }
            .clipped()
            .animation(.easeInOut(duration: 0.4), value: art?.slug)
    }
}

/// Portraits of the characters in the room, top-right. Characters without art are skipped.
private struct CharacterInsets: View {
    let characters: [GameCharacter]
    let onSelect: (GameCharacter) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(characters) { character in
                if let image = Artwork.character(character.id) {
                    Button { onSelect(character) } label: {
                        CharacterPortrait(name: character.name, image: image)
                    }
                    .buttonStyle(.plain)
                    .help("Show \(character.name) close up")
                    .transition(.scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
                }
            }
        }
        .padding(16)
        .animation(.spring(duration: 0.35), value: characters.map(\.id))
    }
}

private struct CharacterPortrait: View {
    let name: String
    let image: NSImage

    static let size: CGFloat = 225

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.size, height: Self.size)
                .clipped()
            Text(name)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.background)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Theme.accent)
        }
        .frame(width: Self.size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, lineWidth: 2))
        .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

/// A character's portrait filling the window, with a small X (or Escape) to close.
/// Whose portrait to show close up. Art comes from Art/NPCs/<artID>.
struct Portrait: Equatable {
    var artID: String
    var name: String
}

private struct CharacterCloseup: View {
    let name: String
    let image: NSImage
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, lineWidth: 2))
                    .shadow(color: .black.opacity(0.8), radius: 24)
                Text(name)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white.opacity(0.15)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityLabel("Close")
            .padding(14)
        }
    }
}

/// Amber-on-black terminal look.
enum Theme {
    static let background = Color(red: 0.07, green: 0.06, blue: 0.05)
    static let text = Color(red: 0.93, green: 0.86, blue: 0.72)
    static let accent = Color(red: 1.0, green: 0.69, blue: 0.25)
    static let dim = Color(red: 0.6, green: 0.55, blue: 0.47)
    static let font = Font.system(size: 14, design: .monospaced)
}
