import AppKit
import PlanetfallEngine
import SwiftUI

@main
struct PlanetfallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var launch = GameLaunch()

    var body: some Scene {
        Window("Planetfall", id: "game") {
            Group {
                switch launch.state {
                case .running(let session):
                    GameView(session: session, sidekick: launch.sidekick, voices: launch.voices)
                case .failed(let message):
                    SetupErrorView(message: message)
                }
            }
            .frame(minWidth: 560, minHeight: 420)
        }
        .defaultSize(width: 820, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Restart Game") { launch.restart() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandMenu("Voices") {
                if let voices = launch.voices {
                    Toggle("Narrator", isOn: Bindable(voices).narratorEnabled)
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                        .disabled(!voices.hasNarrator)
                    Toggle("Character Voices", isOn: Bindable(voices).charactersEnabled)
                        .keyboardShortcut("m", modifiers: [.command, .shift])
                    Toggle("SNARK-9 Voice", isOn: Bindable(voices).sidekickEnabled)
                        .keyboardShortcut("j", modifiers: [.command, .shift])
                        .disabled(!voices.hasSidekick)
                    if !voices.hasNarrator {
                        Text("Add ANTHROPIC_API_KEY to .env for the narrator")
                    }
                } else {
                    Text("Add FISH_API_KEY to .env to hear the game")
                }
            }
            CommandMenu("Sidekick") {
                if let sidekick = launch.sidekick {
                    Toggle("\(sidekick.persona.name) Commentary", isOn: Bindable(sidekick).isEnabled)
                        .keyboardShortcut("k", modifiers: [.command, .shift])
                } else {
                    Text("Add ANTHROPIC_API_KEY to .env to enable commentary")
                }
            }
        }
    }
}

/// Creates the session at launch and keeps any setup error to show in the window.
@MainActor
@Observable
final class GameLaunch {
    enum State {
        case running(GameSession)
        case failed(String)
    }

    private(set) var state: State
    /// The let's-play commentator; nil without an Anthropic API key.
    private(set) var sidekick: Sidekick?
    /// The narrator, characters, and SNARK-9's voices; nil without a Fish API key.
    private(set) var voices: VoiceDirector?

    init() {
        do {
            let session = try GameSession.makeDefault()
            // Created before start() so it sees the opening turn.
            let sidekick = Sidekick.makeDefault(session: session)
            self.sidekick = sidekick
            voices = VoiceDirector.makeDefault(session: session, sidekick: sidekick)
            try session.start()
            state = .running(session)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func restart() {
        guard case .running(let session) = state else { return }
        sidekick?.reset()
        voices?.reset()
        do {
            try session.restart()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched with `swift run`, which starts us as a background process.
        NSApp.setActivationPolicy(.regular)
        // Without a bundle, the Dock would show the generic executable icon.
        if let icon = Artwork.appIcon() { NSApp.applicationIconImage = icon }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct SetupErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Can't start Planetfall", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
    }
}
