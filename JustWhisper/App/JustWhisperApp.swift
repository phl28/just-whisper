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
                Image(systemName: appState.isTranscribing ? "waveform" : "mic")
            }
        }
    }
}
