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
    private(set) var availableLocales: [Locale] = []
    var selectedLocale = Locale(identifier: UserDefaults.standard.selectedLocaleIdentifier)

    let permissions = PermissionsManager()
    let hotkeyManager = GlobalHotkeyManager()
    let deviceManager = AudioDeviceManager()
    let overlay = TranscriptionOverlayWindow()
    let audioService = AudioCaptureService()

    private let textInserter = TextInsertionService()
    private var appleEngine: (any TranscriptionEngine)?
    #if canImport(WhisperKit)
    private var whisperEngine: WhisperKitEngine?
    #endif
    private var session: TranscriptionSession?
    private let settingsController = SettingsWindowController()
    private var appleSupportedLocales: [Locale] = []
    private var appleRetryUsed = false

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

        deviceManager.onSelectedDeviceDisconnected = { [weak self] in
            guard let self, self.isTranscribing else { return }
            Logger.audio.warning("Audio device disconnected during transcription")
            self.stopTranscription()
            self.status = .error("Audio device disconnected")
        }
    }

    func setup() {
        permissions.checkAll()
        if permissions.accessibilityGranted {
            hotkeyManager.register()
        }

        Task {
            await loadSupportedLocales()
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

        appleRetryUsed = false
        finalizedText = ""
        volatileText = ""
        isSpeechDetected = false
        status = .listening

        if UserDefaults.standard.showOverlay {
            overlay.show(appState: self)
        }

        configureSpeechDetection(engine: engine)
        startSessionWith(engine: engine)
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

    // MARK: - Engine Selection

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
        let localeSupported = appleSupportedLocales.contains { locale in
            locale.language.languageCode == selectedLocale.language.languageCode
        }

        if let apple = appleEngine, localeSupported {
            activeEngineName = "Apple Speech"
            return apple
        }

        if !localeSupported, let apple = appleEngine {
            Logger.transcription.info("Locale '\(self.selectedLocale.identifier)' not in Apple's supported list, checking WhisperKit")
        }

        if let whisper = whisperKitFallback() {
            activeEngineName = "WhisperKit"
            return whisper
        }

        if let apple = appleEngine {
            activeEngineName = "Apple Speech"
            Logger.transcription.info("Falling back to Apple engine despite locale mismatch")
            return apple
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

    // MARK: - Session Management

    private func startSessionWith(engine: any TranscriptionEngine) {
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

        session?.stop()
        session = nil

        if case .permissionDenied = error {
            permissions.openMicrophoneSettings()
            status = .error("Microphone permission denied — opening Settings…")
            overlay.hideAfterDelay()
            return
        }

        if #available(macOS 26.0, *),
           originalEngine is AppleSpeechEngine,
           !appleRetryUsed,
           let apple = appleEngine {
            appleRetryUsed = true
            Logger.transcription.info("Retrying with Apple engine (attempt 2)")
            activeEngineName = "Apple Speech (retry)"
            startSessionWith(engine: apple)
            return
        }

        #if canImport(WhisperKit)
        if !(originalEngine is WhisperKitEngine), let fallback = whisperEngine {
            Logger.transcription.info("Falling back to WhisperKit after Apple engine failure")
            activeEngineName = "WhisperKit (fallback)"
            startSessionWith(engine: fallback)
            return
        }
        #endif

        status = .error(error.localizedDescription)
        overlay.hideAfterDelay()
    }

    // MARK: - Locale & Pre-warming

    private func loadSupportedLocales() async {
        var locales: Set<String> = []

        if let apple = appleEngine {
            let appleLocales = await apple.supportedLocales
            appleSupportedLocales = appleLocales
            for locale in appleLocales {
                locales.insert(locale.identifier)
            }
        }

        #if canImport(WhisperKit)
        if let whisper = whisperEngine {
            let whisperLocales = await whisper.supportedLocales
            for locale in whisperLocales {
                locales.insert(locale.identifier)
            }
        }
        #endif

        availableLocales = locales.sorted().map { Locale(identifier: $0) }
    }

    private func prewarmEngines() async {
        let preference = UserDefaults.standard.enginePreference

        if #available(macOS 26.0, *), let apple = appleEngine as? AppleSpeechEngine {
            await apple.prepareModel(for: selectedLocale)
        }

        #if canImport(WhisperKit)
        if preference == .whisperKit || preference == .auto {
            await whisperEngine?.prewarmModel()
        }
        #endif
    }
}
