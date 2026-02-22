#if canImport(WhisperKit)
@preconcurrency import AVFoundation
import Accelerate
import WhisperKit
import OSLog

final class WhisperKitEngine: TranscriptionEngine, @unchecked Sendable {
    private var pipe: WhisperKit?
    private var isStopping = false
    private let modelName: String

    init(modelName: String = "base") {
        self.modelName = modelName
    }

    var isAvailable: Bool {
        get async { true }
    }

    var supportedLocales: [Locale] {
        get async {
            Self.whisperLanguageCodes.map { Locale(identifier: $0) }
        }
    }

    func loadModel() async throws {
        guard pipe == nil else { return }
        Logger.transcription.info("Loading WhisperKit model: \(self.modelName)")
        let config = WhisperKitConfig(model: modelName)
        pipe = try await WhisperKit(config)
        Logger.transcription.info("WhisperKit model loaded")
    }

    func startTranscription(
        audioStream: AsyncStream<AVAudioPCMBuffer>,
        locale: Locale
    ) -> AsyncThrowingStream<TranscriptionResult, Error> {
        isStopping = false
        let engine = self

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await engine.loadModel()

                    guard let pipe = engine.pipe else {
                        throw TranscriptionError.engineUnavailable
                    }

                    var audioSamples: [Float] = []
                    let targetSampleRate: Double = 16000
                    let chunkDuration: Double = 3.0
                    let chunkSize = Int(targetSampleRate * chunkDuration)

                    let languageCode = locale.language.languageCode?.identifier ?? "en"
                    let options = DecodingOptions(
                        task: .transcribe,
                        language: languageCode,
                        temperature: 0.0
                    )

                    for await buffer in audioStream {
                        guard !engine.isStopping else { break }

                        if let samples = engine.convertToMono16kHz(buffer) {
                            audioSamples.append(contentsOf: samples)
                        }

                        if audioSamples.count >= chunkSize {
                            let chunk = Array(audioSamples.prefix(chunkSize))
                            audioSamples.removeFirst(min(chunkSize, audioSamples.count))

                            let results = try await pipe.transcribe(
                                audioArray: chunk,
                                decodeOptions: options
                            )

                            for result in results {
                                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !text.isEmpty else { continue }
                                continuation.yield(TranscriptionResult(
                                    text: text + " ",
                                    isFinal: true
                                ))
                            }
                        }
                    }

                    if !audioSamples.isEmpty && !engine.isStopping && audioSamples.count > 1600 {
                        let results = try await pipe.transcribe(
                            audioArray: audioSamples,
                            decodeOptions: options
                        )
                        for result in results {
                            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { continue }
                            continuation.yield(TranscriptionResult(
                                text: text,
                                isFinal: true
                            ))
                        }
                    }

                    continuation.finish()
                } catch {
                    Logger.transcription.error("WhisperKit error: \(error)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func stopTranscription() async {
        isStopping = true
    }

    private func convertToMono16kHz(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }

        let channelCount = Int(buffer.format.channelCount)
        let inputSampleRate = buffer.format.sampleRate

        var monoSamples = [Float](repeating: 0, count: frameCount)
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for i in 0..<frameCount {
                monoSamples[i] += samples[i]
            }
        }
        if channelCount > 1 {
            var scale = 1.0 / Float(channelCount)
            vDSP_vsmul(monoSamples, 1, &scale, &monoSamples, 1, vDSP_Length(frameCount))
        }

        guard abs(inputSampleRate - 16000) > 1 else {
            return monoSamples
        }

        let ratio = 16000.0 / inputSampleRate
        let outputCount = Int(Double(frameCount) * ratio)
        guard outputCount > 0 else { return nil }

        var outputSamples = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let srcIndex = Double(i) / ratio
            let srcIndexInt = Int(srcIndex)
            let frac = Float(srcIndex - Double(srcIndexInt))

            if srcIndexInt + 1 < frameCount {
                outputSamples[i] = monoSamples[srcIndexInt] * (1 - frac) + monoSamples[srcIndexInt + 1] * frac
            } else if srcIndexInt < frameCount {
                outputSamples[i] = monoSamples[srcIndexInt]
            }
        }

        return outputSamples
    }

    static let whisperLanguageCodes: [String] = [
        "en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr",
        "pl", "ca", "nl", "ar", "sv", "it", "id", "hi", "fi", "vi",
        "he", "uk", "el", "ms", "cs", "ro", "da", "hu", "ta", "no",
        "th", "ur", "hr", "bg", "lt", "la", "mi", "ml", "cy", "sk",
        "te", "fa", "lv", "bn", "sr", "az", "sl", "kn", "et", "mk",
        "br", "eu", "is", "hy", "ne", "mn", "bs", "kk", "sq", "sw",
        "gl", "mr", "pa", "si", "km", "sn", "yo", "so", "af", "oc",
        "ka", "be", "tg", "sd", "gu", "am", "yi", "lo", "uz", "fo",
        "ht", "ps", "tk", "nn", "mt", "sa", "lb", "my", "bo", "tl",
        "mg", "as", "tt", "haw", "ln", "ha", "ba", "jw", "su",
    ]
}
#endif
