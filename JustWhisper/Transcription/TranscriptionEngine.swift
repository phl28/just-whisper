@preconcurrency import AVFoundation

protocol TranscriptionEngine: Sendable {
    var isAvailable: Bool { get async }
    var supportedLocales: [Locale] { get async }
    func startTranscription(
        audioStream: AsyncStream<AVAudioPCMBuffer>,
        locale: Locale
    ) -> AsyncThrowingStream<TranscriptionResult, Error>
    func stopTranscription() async
}
