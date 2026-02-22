@preconcurrency import AVFoundation
import Speech
import OSLog

@available(macOS 26.0, *)
final class AppleSpeechEngine: TranscriptionEngine, @unchecked Sendable {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var detector: SpeechDetector?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?

    var onSpeechDetection: ((Bool) -> Void)?

    var isAvailable: Bool {
        get async { true }
    }

    var supportedLocales: [Locale] {
        get async { await DictationTranscriber.supportedLocales }
    }

    func preferredAudioFormat(for locale: Locale) async -> AVAudioFormat? {
        let transcriber = DictationTranscriber(
            locale: locale,
            preset: .progressiveShortDictation
        )
        let detector = SpeechDetector()
        return await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber, detector]
        )
    }

    func prepareModel(for locale: Locale) async {
        let transcriber = DictationTranscriber(
            locale: locale,
            preset: .progressiveShortDictation
        )
        let detector = SpeechDetector()
        do {
            try await ensureModelAvailable(for: transcriber)

            let options = SpeechAnalyzer.Options(
                priority: .userInitiated,
                modelRetention: .whileInUse
            )
            let analyzer = SpeechAnalyzer(modules: [transcriber, detector], options: options)
            let preferredFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber, detector]
            )
            try await analyzer.prepareToAnalyze(in: preferredFormat)
            await analyzer.cancelAndFinishNow()
            Logger.transcription.info("Apple speech model pre-warmed for \(locale.identifier)")
        } catch {
            Logger.transcription.error("Pre-warm failed: \(error)")
        }
    }

    func startTranscription(
        audioStream: AsyncStream<AVAudioPCMBuffer>,
        locale: Locale
    ) -> AsyncThrowingStream<TranscriptionResult, Error> {
        let transcriber = DictationTranscriber(
            locale: locale,
            preset: .progressiveShortDictation
        )
        self.transcriber = transcriber

        let detector = SpeechDetector()
        self.detector = detector

        let (inputStream, inputCont) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputCont

        let options = SpeechAnalyzer.Options(
            priority: .userInitiated,
            modelRetention: .whileInUse
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber, detector], options: options)
        self.analyzer = analyzer

        startForwardingAudio(from: audioStream, to: inputCont)

        let engine = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await engine.ensureModelAvailable(for: transcriber)
                    try await analyzer.start(inputSequence: inputStream)

                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            await engine.monitorSpeechDetection(detector: detector)
                        }

                        group.addTask {
                            do {
                                for try await result in transcriber.results {
                                    let text = String(result.text.characters)
                                    continuation.yield(TranscriptionResult(
                                        text: text,
                                        isFinal: result.isFinal,
                                        timeRange: result.range
                                    ))
                                }

                                continuation.finish()
                            } catch {
                                Logger.transcription.error("Transcription error: \(error)")
                                continuation.finish(throwing: error)
                            }
                        }

                        await group.next()
                        group.cancelAll()
                    }
                } catch {
                    Logger.transcription.error("Analyzer start error: \(error)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func stopTranscription() async {
        inputContinuation?.finish()
        inputContinuation = nil
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            Logger.transcription.error("Error finalizing: \(error)")
            await analyzer?.cancelAndFinishNow()
        }
        analyzer = nil
        transcriber = nil
        detector = nil
    }

    private func monitorSpeechDetection(detector: SpeechDetector) async {
        do {
            for try await result in detector.results {
                onSpeechDetection?(result.speechDetected)
            }
        } catch {
            Logger.transcription.debug("Speech detection ended: \(error)")
        }
    }

    private nonisolated func startForwardingAudio(
        from audioStream: AsyncStream<AVAudioPCMBuffer>,
        to continuation: AsyncStream<AnalyzerInput>.Continuation
    ) {
        Task {
            for await buffer in audioStream {
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
            continuation.finish()
        }
    }

    private func ensureModelAvailable(for transcriber: DictationTranscriber) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        switch status {
        case .installed:
            Logger.transcription.info("Speech model already installed")
        case .supported, .downloading:
            Logger.transcription.info("Downloading speech model...")
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
                Logger.transcription.info("Speech model downloaded")
            }
        case .unsupported:
            throw TranscriptionError.localeNotSupported
        @unknown default:
            break
        }
    }
}

enum TranscriptionError: LocalizedError {
    case localeNotSupported
    case engineUnavailable
    case permissionDenied
    case audioDeviceNotFound
    case audioDeviceDisconnected
    case engineFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .localeNotSupported: "The selected language is not supported by this engine."
        case .engineUnavailable: "No transcription engine is available."
        case .permissionDenied: "Speech recognition permission was denied."
        case .audioDeviceNotFound: "The selected audio device could not be found."
        case .audioDeviceDisconnected: "The audio device was disconnected."
        case .engineFailed(let error): "Transcription failed: \(error.localizedDescription)"
        }
    }
}
