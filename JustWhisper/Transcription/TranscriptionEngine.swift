@preconcurrency import AVFoundation

protocol TranscriptionEngine: Sendable {
    var isAvailable: Bool { get async }
    var supportedLocales: [Locale] { get async }
    func preferredAudioFormat(for locale: Locale) async -> AVAudioFormat?
    func startTranscription(
        audioStream: AsyncStream<AVAudioPCMBuffer>,
        locale: Locale
    ) -> AsyncThrowingStream<TranscriptionResult, Error>
    func stopTranscription() async
}

extension TranscriptionEngine {
    func preferredAudioFormat(for locale: Locale) async -> AVAudioFormat? { nil }
}
