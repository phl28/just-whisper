import SwiftUI

@main
struct JustWhisperApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Label {
                Text("Just Whisper")
            } icon: {
                Image(systemName: menuBarIcon)
            }
        }
    }

    private var menuBarIcon: String {
        switch appState.status {
        case .listening: "waveform"
        case .processing: "ellipsis.circle"
        case .error: "exclamationmark.triangle"
        case .idle: "mic"
        }
    }
}
