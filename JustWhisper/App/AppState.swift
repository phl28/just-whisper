import SwiftUI
import ServiceManagement
import OSLog

@Observable
@MainActor
final class AppState {
    enum Status {
        case idle
        case listening
        case processing
        case error(String)
    }

    private(set) var status: Status = .idle
    private(set) var finalizedText = ""
    private(set) var volatileText = ""
    var selectedLocale = Locale(identifier: UserDefaults.standard.selectedLocaleIdentifier)

    let permissions = PermissionsManager()
    let hotkeyManager = GlobalHotkeyManager()
    let deviceManager = AudioDeviceManager()
    let overlay = TranscriptionOverlayWindow()

    private let audioService = AudioCaptureService()
    private let textInserter = TextInsertionService()
    private var engine: (any TranscriptionEngine)?
    private var session: TranscriptionSession?
    private let settingsController = SettingsWindowController()

    var isTranscribing: Bool {
        switch status {
        case .listening, .processing: true
        default: false
        }
    }

    init() {
        if #available(macOS 26.0, *) {
            engine = AppleSpeechEngine()
        }

        if let modeRaw = UserDefaults.standard.string(forKey: Defaults.hotkeyMode),
           let mode = GlobalHotkeyManager.Mode(rawValue: modeRaw) {
            hotkeyManager.mode = mode
        }

        hotkeyManager.onActivate = { [weak self] in
            self?.toggleTranscription()
        }
        hotkeyManager.onDeactivate = { [weak self] in
            if self?.hotkeyManager.mode == .holdToTalk {
                self?.stopTranscription()
            }
        }
    }

    func setup() {
        permissions.checkAll()
        if permissions.accessibilityGranted {
            hotkeyManager.register()
        }
    }

    func toggleTranscription() {
        if isTranscribing {
            stopTranscription()
        } else {
            startTranscription()
        }
    }

    func startTranscription() {
        guard !isTranscribing else { return }
        guard let engine else {
            status = .error("No transcription engine available")
            return
        }

        finalizedText = ""
        volatileText = ""
        status = .listening

        if UserDefaults.standard.showOverlay {
            overlay.show(appState: self)
        }

        let shouldAutoInsert = UserDefaults.standard.autoInsert
        let session = TranscriptionSession(
            audioService: audioService,
            engine: engine,
            textInserter: shouldAutoInsert ? textInserter : nil,
            locale: selectedLocale
        )
        session.onUpdate = { [weak self] finalized, volatile in
            self?.finalizedText = finalized
            self?.volatileText = volatile
        }
        self.session = session

        Task {
            do {
                try await session.start()
                status = .idle
                overlay.hideAfterDelay()
            } catch {
                Logger.transcription.error("Failed to start: \(error)")
                status = .error(error.localizedDescription)
            }
        }
    }

    func stopTranscription() {
        session?.stop()
        session = nil
        volatileText = ""
        status = .idle
        overlay.hideAfterDelay()
    }

    func showSettings() {
        settingsController.show(appState: self)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.ui.error("Failed to set launch at login: \(error)")
        }
    }

    var displayText: String {
        if volatileText.isEmpty {
            return finalizedText
        }
        return finalizedText + volatileText
    }
}
