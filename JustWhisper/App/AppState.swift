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
    private(set) var isSpeechDetected = false
    private(set) var activeEngineName = ""
    var selectedLocale = Locale(identifier: UserDefaults.standard.selectedLocaleIdentifier)

    let permissions = PermissionsManager()
    let hotkeyManager = GlobalHotkeyManager()
    let deviceManager = AudioDeviceManager()
    let overlay = TranscriptionOverlayWindow()

    private let audioService = AudioCaptureService()
    private let textInserter = TextInsertionService()
    private var appleEngine: (any TranscriptionEngine)?
    #if canImport(WhisperKit)
    private var whisperEngine: WhisperKitEngine?
    #endif
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
            appleEngine = AppleSpeechEngine()
        }

        #if canImport(WhisperKit)
        whisperEngine = WhisperKitEngine(
            modelName: UserDefaults.standard.whisperKitModel
        )
        #endif

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

        Task {
            await prewarmEngines()
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

        let engine = resolveEngine()
        guard let engine else {
            status = .error("No transcription engine available")
            return
        }

        finalizedText = ""
        volatileText = ""
        isSpeechDetected = false
        status = .listening

        if UserDefaults.standard.showOverlay {
            overlay.show(appState: self)
        }

        configureSpeechDetection(engine: engine)

        let shouldAutoInsert = UserDefaults.standard.autoInsert
        let silenceTimeout = UserDefaults.standard.silenceTimeoutSeconds
        let session = TranscriptionSession(
            audioService: audioService,
            engine: engine,
            textInserter: shouldAutoInsert ? textInserter : nil,
            locale: selectedLocale,
            silenceTimeout: silenceTimeout
        )
        session.onUpdate = { [weak self] finalized, volatile in
            self?.finalizedText = finalized
            self?.volatileText = volatile
        }
        session.onSilenceTimeout = { [weak self] in
            self?.stopTranscription()
        }
        self.session = session

        Task {
            do {
                try await session.start()
                status = .idle
                overlay.hideAfterDelay()
            } catch let error as TranscriptionError {
                handleTranscriptionError(error, originalEngine: engine)
            } catch {
                Logger.transcription.error("Failed to start: \(error)")
                status = .error(error.localizedDescription)
                overlay.hideAfterDelay()
            }
        }
    }

    func stopTranscription() {
        session?.stop()
        session = nil
        volatileText = ""
        isSpeechDetected = false
        activeEngineName = ""
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

    var isWhisperKitAvailable: Bool {
        #if canImport(WhisperKit)
        return true
        #else
        return false
        #endif
    }

    private func resolveEngine() -> (any TranscriptionEngine)? {
        let preference = UserDefaults.standard.enginePreference

        switch preference {
        case .apple:
            if let engine = appleEngine {
                activeEngineName = "Apple Speech"
                return engine
            }
            Logger.transcription.warning("Apple engine requested but unavailable, trying fallback")
            return fallbackEngine()

        case .whisperKit:
            if let engine = whisperKitFallback() {
                activeEngineName = "WhisperKit"
                return engine
            }
            Logger.transcription.warning("WhisperKit requested but unavailable, trying Apple")
            if let engine = appleEngine {
                activeEngineName = "Apple Speech"
                return engine
            }
            return nil

        case .auto:
            return autoSelectEngine()
        }
    }

    private func autoSelectEngine() -> (any TranscriptionEngine)? {
        if let apple = appleEngine {
            activeEngineName = "Apple Speech"
            return apple
        }

        if let whisper = whisperKitFallback() {
            activeEngineName = "WhisperKit"
            return whisper
        }

        return nil
    }

    private func fallbackEngine() -> (any TranscriptionEngine)? {
        if let whisper = whisperKitFallback() {
            activeEngineName = "WhisperKit"
            return whisper
        }
        if let apple = appleEngine {
            activeEngineName = "Apple Speech"
            return apple
        }
        return nil
    }

    private func whisperKitFallback() -> (any TranscriptionEngine)? {
        #if canImport(WhisperKit)
        return whisperEngine
        #else
        return nil
        #endif
    }

    private func configureSpeechDetection(engine: any TranscriptionEngine) {
        if #available(macOS 26.0, *), let appleEngine = engine as? AppleSpeechEngine {
            appleEngine.onSpeechDetection = { [weak self] detected in
                Task { @MainActor in
                    self?.isSpeechDetected = detected
                }
            }
        }
    }

    private func handleTranscriptionError(_ error: TranscriptionError, originalEngine: any TranscriptionEngine) {
        Logger.transcription.error("Transcription error: \(error.localizedDescription)")

        #if canImport(WhisperKit)
        if !(originalEngine is WhisperKitEngine), let fallback = whisperEngine {
            Logger.transcription.info("Falling back to WhisperKit after Apple engine failure")
            activeEngineName = "WhisperKit (fallback)"
            retryWithEngine(fallback)
            return
        }
        #endif

        status = .error(error.localizedDescription)
        overlay.hideAfterDelay()
    }

    private func retryWithEngine(_ engine: any TranscriptionEngine) {
        let shouldAutoInsert = UserDefaults.standard.autoInsert
        let silenceTimeout = UserDefaults.standard.silenceTimeoutSeconds
        let session = TranscriptionSession(
            audioService: audioService,
            engine: engine,
            textInserter: shouldAutoInsert ? textInserter : nil,
            locale: selectedLocale,
            silenceTimeout: silenceTimeout
        )
        session.onUpdate = { [weak self] finalized, volatile in
            self?.finalizedText = finalized
            self?.volatileText = volatile
        }
        session.onSilenceTimeout = { [weak self] in
            self?.stopTranscription()
        }
        self.session = session

        Task {
            do {
                try await session.start()
                status = .idle
                overlay.hideAfterDelay()
            } catch {
                Logger.transcription.error("Fallback engine also failed: \(error)")
                status = .error(error.localizedDescription)
                overlay.hideAfterDelay()
            }
        }
    }

    private func prewarmEngines() async {
        if #available(macOS 26.0, *), let apple = appleEngine as? AppleSpeechEngine {
            await apple.prepareModel(for: selectedLocale)
        }
    }
}
