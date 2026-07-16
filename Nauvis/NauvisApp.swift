import SwiftUI

@main
struct NauvisApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 900, height: 650)
        .windowToolbarStyle(.unified)
        .commands {
            SessionCommands()
        }
    }
}

private struct SessionCommands: Commands {
    @FocusedObject private var appState: AppState?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                appState?.newSession()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Close Tab") {
                appState?.closeCurrentTab()
            }
            .keyboardShortcut("w", modifiers: .command)
        }
    }
}
