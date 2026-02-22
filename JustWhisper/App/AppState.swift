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

    private let audioService = AudioCaptureService()
    private var engine: (any TranscriptionEngine)?
    private var transcriptionTask: Task<Void, Never>?

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

        transcriptionTask = Task {
            let granted = await audioService.requestPermission()
            guard granted else {
                status = .error("Microphone permission denied")
                return
            }

            let audioStream = audioService.startCapture()
            let resultStream = engine.startTranscription(
                audioStream: audioStream,
                locale: selectedLocale
            )

            do {
                for try await result in resultStream {
                    if result.isFinal {
                        finalizedText += result.text
                        volatileText = ""
                        Logger.transcription.debug("Final: \(result.text)")
                    } else {
                        volatileText = result.text
                        Logger.transcription.debug("Volatile: \(result.text)")
                    }
                }
                status = .idle
            } catch {
                Logger.transcription.error("Transcription failed: \(error)")
                status = .error(error.localizedDescription)
            }
        }
    }

    func stopTranscription() {
        audioService.stopCapture()

        Task {
            await engine?.stopTranscription()
        }

        transcriptionTask?.cancel()
        transcriptionTask = nil
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
