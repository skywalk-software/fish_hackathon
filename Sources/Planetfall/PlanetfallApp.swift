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
                    GameView(session: session, sidekick: launch.sidekick, voices: launch.voices,
                             achievements: launch.achievements)
                case .failed(let message):
                    SetupErrorView(message: message)
                }
            }
            .frame(minWidth: 560, minHeight: 420)
            // The player's chosen Dock icon. Re-applied when achievements change, so a chosen
            // icon that becomes locked (achievements reset) falls back to the default.
            .onAppear { launch.dockIcons.apply() }
            .onChange(of: launch.achievements.earned) { _, _ in launch.dockIcons.apply() }
            // The app is always dark; this keeps system-drawn parts (text cursor, scrollbars,
            // selection) readable when macOS itself is in Light Mode.
            .preferredColorScheme(.dark)
        }
        .defaultSize(width: 820, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Restart Game") { launch.restart() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandMenu("Narrator") {
                if let voices = launch.voices {
                    Picker("Narrator", selection: Bindable(voices).narratorChoice) {
                        ForEach(VoiceDirector.NarratorChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if !voices.hasNarrator {
                        Divider()
                        Text("No ANTHROPIC_API_KEY: Embellished Text reads the original text")
                    }
                } else {
                    Text("Add FISH_API_KEY to .env to hear the narrator")
                }
            }
            CommandMenu("Voices") {
                if let voices = launch.voices {
                    Toggle("Character Voices", isOn: Bindable(voices).charactersEnabled)
                        .keyboardShortcut("m", modifiers: [.command, .shift])
                    Toggle("SNARK-9 Voice", isOn: Bindable(voices).sidekickEnabled)
                        .keyboardShortcut("j", modifiers: [.command, .shift])
                        .disabled(!voices.hasSidekick)
                    Toggle("Sound Effects", isOn: Bindable(voices).effectsEnabled)
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    Divider()
                    Toggle("Talking Portraits", isOn: Bindable(voices).talkingPortraitsEnabled)
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

        Settings {
            SettingsView(dockIcons: launch.dockIcons, achievements: launch.achievements)
                .preferredColorScheme(.dark)
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
    /// Achievements earned on this Mac (kept across games and launches).
    let achievements = AchievementStore()
    /// Which Dock icon to show; some unlock with achievements.
    let dockIcons: DockIconSettings

    init() {
        dockIcons = DockIconSettings(achievements: achievements)
        do {
            let session = try GameSession.makeDefault()
            session.achievements = achievements
            // Created before start() so it sees the opening turn.
            let sidekick = Sidekick.makeDefault(session: session)
            self.sidekick = sidekick
            voices = VoiceDirector.makeDefault(session: session, sidekick: sidekick)
            try session.start()
            state = .running(session)
            // Note the Fish balance at each launch, to estimate how fast credit is going.
            if let key = FishAPIKey.load() {
                Task { if let credit = try? await FishCredit.fetch(apiKey: key) { FishCreditHistory.shared.add(credit) } }
            }
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
        // Without a bundle, the Dock would show the generic executable icon until the game
        // window applies the chosen one.
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
