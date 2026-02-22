import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            statusRow

            if !appState.permissions.allGranted {
                Divider()
                permissionsSection
            }

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
                .disabled(!appState.permissions.microphoneGranted)
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

            hotkeySection

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(4)
        .onAppear {
            appState.setup()
        }
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

    @ViewBuilder
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !appState.permissions.microphoneGranted {
                Button("Grant Microphone Access") {
                    Task { await appState.permissions.requestMicrophone() }
                }
            }
            if !appState.permissions.accessibilityGranted {
                Button("Grant Accessibility Access") {
                    appState.permissions.requestAccessibility()
                    appState.permissions.checkAccessibility()
                    if appState.permissions.accessibilityGranted {
                        appState.hotkeyManager.register()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var hotkeySection: some View {
        HStack {
            Text("Hotkey: Double-tap ⌥")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: Binding(
                get: { appState.hotkeyManager.mode },
                set: { appState.hotkeyManager.mode = $0 }
            )) {
                Text("Toggle").tag(GlobalHotkeyManager.Mode.toggle)
                Text("Hold").tag(GlobalHotkeyManager.Mode.holdToTalk)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
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
        case .idle:
            if appState.hotkeyManager.isRegistered {
                return "Ready — double-tap ⌥ to dictate"
            }
            return "Ready"
        case .listening: return "Listening..."
        case .processing: return "Processing..."
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
