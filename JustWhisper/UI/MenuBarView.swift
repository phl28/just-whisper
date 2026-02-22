import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            statusRow

            Divider()

            if appState.isTranscribing {
                Button("Stop Transcription") {
                    appState.stopTranscription()
                }
                .keyboardShortcut("s")
            } else {
                Button("Start Transcription") {
                    appState.startTranscription()
                }
                .keyboardShortcut("s")
            }

            if !appState.displayText.isEmpty {
                Divider()
                Text(appState.displayText)
                    .font(.caption)
                    .lineLimit(5)
                    .frame(maxWidth: 280, alignment: .leading)

                Button("Copy Text") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.displayText, forType: .string)
                }
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(4)
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle: .gray
        case .listening: .green
        case .processing: .orange
        case .error: .red
        }
    }

    private var statusLabel: String {
        switch appState.status {
        case .idle: "Ready"
        case .listening: "Listening..."
        case .processing: "Processing..."
        case .error(let msg): "Error: \(msg)"
        }
    }
}
