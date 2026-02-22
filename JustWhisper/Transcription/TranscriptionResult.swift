import CoreMedia

struct TranscriptionResult: Sendable {
    let text: String
    let isFinal: Bool
    let confidence: Double?
    let timeRange: CMTimeRange?

    init(text: String, isFinal: Bool, confidence: Double? = nil, timeRange: CMTimeRange? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.timeRange = timeRange
    }
}
