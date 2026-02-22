import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState

    @AppStorage(Defaults.showOverlay) private var showOverlay = true
    @AppStorage(Defaults.autoInsert) private var autoInsert = true
    @AppStorage(Defaults.launchAtLogin) private var launchAtLogin = false
    @AppStorage(Defaults.enginePreference) private var enginePreference = EnginePreference.auto.rawValue
    @AppStorage(Defaults.whisperKitModel) private var whisperKitModel = "base"

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            hotkeyTab
                .tabItem { Label("Hotkey", systemImage: "command") }
            audioTab
                .tabItem { Label("Audio", systemImage: "mic") }
        }
        .padding(20)
        .frame(width: 460, height: 440)
    }

    @ViewBuilder
    private var generalTab: some View {
        Form {
            Section("Engine") {
                Picker("Transcription engine", selection: $enginePreference) {
                    Text("Auto (Recommended)").tag(EnginePreference.auto.rawValue)
                    Text("Apple Speech").tag(EnginePreference.apple.rawValue)
                    if appState.isWhisperKitAvailable {
                        Text("WhisperKit").tag(EnginePreference.whisperKit.rawValue)
                    }
                }

                if !appState.activeEngineName.isEmpty {
                    HStack {
                        Text("Active engine:")
                        Text(appState.activeEngineName)
                            .foregroundStyle(.secondary)
                    }
                }

                if appState.isWhisperKitAvailable {
                    Picker("WhisperKit model", selection: $whisperKitModel) {
                        Text("Tiny (fastest)").tag("tiny")
                        Text("Base (balanced)").tag("base")
                        Text("Small").tag("small")
                        Text("Medium").tag("medium")
                        Text("Large v3 (best quality)").tag("large-v3")
                    }
                }
            }

            Section("Transcription") {
                Picker("Language", selection: $appState.selectedLocale) {
                    Text("System Default (\(Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? "Unknown"))")
                        .tag(Locale.current)

                    if !appState.availableLocales.isEmpty {
                        Divider()
                        ForEach(appState.availableLocales, id: \.identifier) { locale in
                            Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                                .tag(locale)
                        }
                    }
                }

                Toggle("Show floating overlay", isOn: $showOverlay)
                Toggle("Auto-insert into active field", isOn: $autoInsert)
            }

            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        appState.setLaunchAtLogin(newValue)
                    }
            }

            Section("Permissions") {
                HStack {
                    Label(
                        appState.permissions.microphoneGranted ? "Microphone: Granted" : "Microphone: Not Granted",
                        systemImage: appState.permissions.microphoneGranted ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(appState.permissions.microphoneGranted ? .green : .red)

                    Spacer()

                    if !appState.permissions.microphoneGranted {
                        Button("Open Settings") {
                            appState.permissions.openMicrophoneSettings()
                        }
                    }
                }

                HStack {
                    Label(
                        appState.permissions.accessibilityGranted ? "Accessibility: Granted" : "Accessibility: Not Granted",
                        systemImage: appState.permissions.accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(appState.permissions.accessibilityGranted ? .green : .red)

                    Spacer()

                    if !appState.permissions.accessibilityGranted {
                        Button("Open Settings") {
                            appState.permissions.openAccessibilitySettings()
                        }
                    }
                }

                HStack {
                    Label(
                        appState.permissions.speechRecognitionGranted ? "Speech Recognition: Granted" : "Speech Recognition: Not Granted",
                        systemImage: appState.permissions.speechRecognitionGranted ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(appState.permissions.speechRecognitionGranted ? .green : .red)

                    Spacer()

                    if !appState.permissions.speechRecognitionGranted {
                        Button("Open Settings") {
                            appState.permissions.openSpeechRecognitionSettings()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var hotkeyTab: some View {
        Form {
            Section("Activation") {
                Picker("Mode", selection: Binding(
                    get: { appState.hotkeyManager.mode },
                    set: { appState.hotkeyManager.mode = $0 }
                )) {
                    Text("Toggle (double-tap to start/stop)").tag(GlobalHotkeyManager.Mode.toggle)
                    Text("Hold to talk (hold to record, release to stop)").tag(GlobalHotkeyManager.Mode.holdToTalk)
                }
                .pickerStyle(.radioGroup)
            }

            Section("Shortcut") {
                HStack {
                    Text("Current shortcut:")
                    Text("Double-tap Right ⌥ Option")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }

                HStack {
                    Text("Status:")
                    Text(appState.hotkeyManager.isRegistered ? "Active" : "Not registered")
                        .foregroundStyle(appState.hotkeyManager.isRegistered ? .green : .red)
                }
            }
        }
    }

    @ViewBuilder
    private var audioTab: some View {
        Form {
            Section("Input Device") {
                Picker("Microphone", selection: Binding(
                    get: { appState.deviceManager.selectedDeviceUID ?? "" },
                    set: { appState.deviceManager.selectedDeviceUID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("System Default").tag("")
                    ForEach(appState.deviceManager.inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }

                Button("Refresh Devices") {
                    appState.deviceManager.refreshDevices()
                }
            }

            Section("Level") {
                AudioLevelView(level: appState.audioService.currentLevel)
                    .frame(height: 20)

                Text(appState.audioService.isCapturing ? "Monitoring active" : "Start transcription to see levels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AudioLevelView: View {
    let level: Float

    private var normalizedLevel: CGFloat {
        let clamped = max(min(CGFloat(level), 0), -60)
        return (clamped + 60) / 60
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)

                RoundedRectangle(cornerRadius: 4)
                    .fill(levelColor)
                    .frame(width: geometry.size.width * normalizedLevel)
                    .animation(.linear(duration: 0.1), value: normalizedLevel)
            }
        }
    }

    private var levelColor: Color {
        if normalizedLevel > 0.8 {
            return .red
        } else if normalizedLevel > 0.5 {
            return .yellow
        }
        return .green
    }
}
