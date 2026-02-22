import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.justwhisper"

    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let integration = Logger(subsystem: subsystem, category: "integration")
}
