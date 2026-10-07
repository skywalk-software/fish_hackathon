import PlanetfallEngine
import SwiftUI

struct GameView: View {
    let session: GameSession

    @State private var input = ""
    @State private var history: [String] = []
    @State private var historyIndex: Int?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            StatusBar(status: session.status)
            Divider()
            TranscriptView(entries: session.transcript)
            Divider()
            inputBar
        }
        .background(Theme.background)
        .onAppear { inputFocused = true }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text(">")
                .foregroundStyle(Theme.accent)
            TextField(text: $input) {
                Text(session.isRunning ? "What next?" : "The game has ended").foregroundStyle(Theme.dim)
            }
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .disabled(!session.isRunning)
                .onSubmit(submit)
                .onKeyPress(.upArrow) { recallHistory(-1) }
                .onKeyPress(.downArrow) { recallHistory(1) }
        }
        .font(Theme.font)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
