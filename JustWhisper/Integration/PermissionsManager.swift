import AppKit
@preconcurrency import AVFoundation
import OSLog

@Observable
@MainActor
final class PermissionsManager {
    private(set) var microphoneGranted = false
    private(set) var accessibilityGranted = false

    func checkAll() {
        checkMicrophone()
        checkAccessibility()
    }

    func checkMicrophone() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            microphoneGranted = true
        case .denied:
            microphoneGranted = false
        case .undetermined:
            microphoneGranted = false
        @unknown default:
            microphoneGranted = false
        }
    }

    func requestMicrophone() async {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        microphoneGranted = granted
    }

    func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    var allGranted: Bool {
        microphoneGranted && accessibilityGranted
    }
}
