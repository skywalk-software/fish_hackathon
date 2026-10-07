import PlanetfallEngine
import SwiftUI

struct GameView: View {
    let session: GameSession

    @State private var input = ""
    @State private var history: [String] = []
    @State private var historyIndex: Int?
    @State private var pushToTalk = PushToTalk()
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            StatusBar(status: session.status)
            RoomArtView(location: session.status?.location)
            Divider()
            TranscriptView(entries: session.transcript)
            Divider()
            inputBar
        }
        .background(Theme.background)
        .onAppear {
            inputFocused = true
            pushToTalk.activate(canListen: { session.isRunning }, onTranscript: sendVoiceCommand)
        }
        .onDisappear { pushToTalk.deactivate() }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text(">")
                .foregroundStyle(Theme.accent)
            TextField(text: $input) {
                Text(placeholder).foregroundStyle(Theme.dim)
            }
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .disabled(!session.isRunning)
                .onSubmit(submit)
                .onKeyPress(.upArrow) { recallHistory(-1) }
                .onKeyPress(.downArrow) { recallHistory(1) }
            MicButton(pushToTalk: pushToTalk)
                .disabled(!session.isRunning || pushToTalk.unavailableReason != nil)
        }
        .font(Theme.font)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var placeholder: String {
        guard session.isRunning else { return "The game has ended" }
        switch pushToTalk.phase {
        case .listening: return "Listening… release to send"
        case .transcribing: return "Transcribing…"
        case .idle: return pushToTalk.notice ?? (pushToTalk.unavailableReason == nil ? "What next? (hold ⌥ to speak)" : "What next?")
        }
    }

    private func sendVoiceCommand(_ command: String) {
        session.send(command)
        history.append(command)
        historyIndex = nil
    }

    private func submit() {
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
            case .transcribing:
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

    var body: some View {
        let image = location.flatMap(RoomArt.image(for:))
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
                        .id(location)
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
            .animation(.easeInOut(duration: 0.4), value: location)
    }
}

private struct TranscriptView: View {
    let entries: [TranscriptEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(entries) { entry in
                        row(for: entry).id(entry.id)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Stay pinned to the latest text when the art panel resizes the transcript.
            .defaultScrollAnchor(.bottom)
            .onChange(of: entries.last?.id) { _, last in
                guard let last else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
        .font(Theme.font)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func row(for entry: TranscriptEntry) -> some View {
        switch entry {
        case .narration(_, let text):
            Text(text).foregroundStyle(Theme.text)
        case .command(_, let text):
            Text(verbatim: "> \(text)").foregroundStyle(Theme.accent)
        case .system(_, let text):
            Text(text).foregroundStyle(Theme.dim).italic()
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
