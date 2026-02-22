import SwiftUI
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
    var selectedLocale = Locale.current

    let permissions = PermissionsManager()
    let hotkeyManager = GlobalHotkeyManager()

    private let audioService = AudioCaptureService()
    private let textInserter = TextInsertionService()
    private var engine: (any TranscriptionEngine)?
    private var session: TranscriptionSession?

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

        let session = TranscriptionSession(
            audioService: audioService,
            engine: engine,
            textInserter: textInserter,
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
    }

    var displayText: String {
        if volatileText.isEmpty {
            return finalizedText
        }
        return finalizedText + volatileText
    }
}
