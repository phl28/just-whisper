@preconcurrency import AVFoundation
import OSLog

@MainActor
final class TranscriptionSession {
    private let audioService: AudioCaptureService
    private let engine: any TranscriptionEngine
    private let textInserter: TextInsertionService
    private let locale: Locale

    private var transcriptionTask: Task<Void, Never>?
    private(set) var finalizedText = ""
    private(set) var volatileText = ""
    private(set) var isRunning = false

    var onUpdate: ((String, String) -> Void)?

    init(
        audioService: AudioCaptureService,
        engine: any TranscriptionEngine,
        textInserter: TextInsertionService,
        locale: Locale
    ) {
        self.audioService = audioService
        self.engine = engine
        self.textInserter = textInserter
        self.locale = locale
    }

    func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        finalizedText = ""
        volatileText = ""

        let granted = await audioService.requestPermission()
        guard granted else {
            isRunning = false
            throw TranscriptionError.permissionDenied
        }

        let audioStream = audioService.startCapture()
        let resultStream = engine.startTranscription(
            audioStream: audioStream,
            locale: locale
        )

        transcriptionTask = Task {
            var lastInsertedLength = 0

            do {
                for try await result in resultStream {
                    if result.isFinal {
                        finalizedText += result.text
                        volatileText = ""

                        let newText = String(finalizedText.dropFirst(lastInsertedLength))
                        if !newText.isEmpty {
                            textInserter.insertText(newText)
                            lastInsertedLength = finalizedText.count
                        }

                        Logger.transcription.debug("Final: \(result.text)")
                    } else {
                        volatileText = result.text
                        Logger.transcription.debug("Volatile: \(result.text)")
                    }

                    onUpdate?(finalizedText, volatileText)
                }
            } catch {
                Logger.transcription.error("Session error: \(error)")
            }

            isRunning = false
            onUpdate?(finalizedText, volatileText)
        }
    }

    func stop() {
        audioService.stopCapture()

        Task {
            await engine.stopTranscription()
        }

        transcriptionTask?.cancel()
        transcriptionTask = nil
        isRunning = false
    }
}
