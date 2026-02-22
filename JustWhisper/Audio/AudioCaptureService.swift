@preconcurrency import AVFoundation
import Accelerate
import OSLog

@Observable
final class AudioCaptureService: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private(set) var isCapturing = false
    private(set) var currentLevel: Float = -160

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

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.updateLevel(from: buffer)
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
        currentLevel = -160
        Logger.audio.info("Audio capture stopped")
    }

    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var rms: Float = 0
        vDSP_measqv(channelData[0], 1, &rms, vDSP_Length(frameCount))
        let db = 20 * log10(max(sqrt(rms), 1e-10))

        currentLevel = db
    }
}
