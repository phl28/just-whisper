@preconcurrency import AVFoundation
import OSLog

@MainActor
final class TranscriptionSession {
    private let audioService: AudioCaptureService
    private let engine: any TranscriptionEngine
    private let textInserter: TextInsertionService?
    private let locale: Locale
    private let silenceTimeout: TimeInterval

    private var transcriptionTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private(set) var finalizedText = ""
    private(set) var volatileText = ""
    private(set) var isRunning = false

    var onUpdate: ((String, String) -> Void)?
    var onSilenceTimeout: (() -> Void)?

    init(
        audioService: AudioCaptureService,
        engine: any TranscriptionEngine,
        textInserter: TextInsertionService?,
        locale: Locale,
        silenceTimeout: TimeInterval = 30
    ) {
        self.audioService = audioService
        self.engine = engine
        self.textInserter = textInserter
        self.locale = locale
        self.silenceTimeout = silenceTimeout
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

        let preferredFormat = await engine.preferredAudioFormat(for: locale)
        let audioStream = audioService.startCapture(format: preferredFormat)
        let resultStream = engine.startTranscription(
            audioStream: audioStream,
            locale: locale
        )

        var lastResultTime = Date()

        if silenceTimeout > 0 {
            silenceTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard let self, self.isRunning else { break }

                    if Date().timeIntervalSince(lastResultTime) >= self.silenceTimeout {
                        Logger.transcription.info("Silence timeout reached (\(self.silenceTimeout)s)")
                        self.onSilenceTimeout?()
                        break
                    }
                }
            }
        }

        transcriptionTask = Task {
            var lastInsertedLength = 0

            do {
                for try await result in resultStream {
                    lastResultTime = Date()

                    if result.isFinal {
                        finalizedText += result.text
                        volatileText = ""

                        let newText = String(finalizedText.dropFirst(lastInsertedLength))
                        if !newText.isEmpty {
                            textInserter?.insertText(newText)
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

        silenceTask?.cancel()
        silenceTask = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isRunning = false
    }
}
