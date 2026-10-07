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
                    GameView(session: session)
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

    init() {
        do {
            let session = try GameSession.makeDefault()
            try session.start()
            state = .running(session)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func restart() {
        guard case .running(let session) = state else { return }
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
