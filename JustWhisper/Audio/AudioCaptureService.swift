@preconcurrency import AVFoundation
import OSLog

@Observable
final class AudioCaptureService: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private(set) var isCapturing = false

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startCapture(format: AVAudioFormat? = nil) -> AsyncStream<AVAudioPCMBuffer> {
        let inputNode = engine.inputNode
        let recordingFormat = format ?? inputNode.outputFormat(forBus: 0)

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.continuation = continuation

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            continuation.yield(buffer)
        }

        do {
            try engine.start()
            isCapturing = true
            Logger.audio.info("Audio capture started, format: \(recordingFormat)")
        } catch {
            Logger.audio.error("Failed to start audio engine: \(error)")
            continuation.finish()
            self.continuation = nil
        }

        return stream
    }

    func stopCapture() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        isCapturing = false
        Logger.audio.info("Audio capture stopped")
    }
}
