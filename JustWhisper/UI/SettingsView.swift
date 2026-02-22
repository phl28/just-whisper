import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState

    @AppStorage(Defaults.showOverlay) private var showOverlay = true
    @AppStorage(Defaults.autoInsert) private var autoInsert = true
    @AppStorage(Defaults.launchAtLogin) private var launchAtLogin = false

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
        .frame(width: 460, height: 340)
    }

    @ViewBuilder
    private var generalTab: some View {
        Form {
            Section("Transcription") {
                Picker("Language", selection: $appState.selectedLocale) {
                    Text("System Default (\(Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? "Unknown"))")
                        .tag(Locale.current)
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
        }
    }
}
