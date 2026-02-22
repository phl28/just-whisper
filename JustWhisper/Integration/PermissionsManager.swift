import AppKit
@preconcurrency import AVFoundation
import Speech
import OSLog

@Observable
@MainActor
final class PermissionsManager {
    private(set) var microphoneGranted = false
    private(set) var accessibilityGranted = false
    private(set) var speechRecognitionGranted = false

    func checkAll() {
        checkMicrophone()
        checkAccessibility()
        checkSpeechRecognition()
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

    func checkSpeechRecognition() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechRecognitionGranted = true
        case .denied, .restricted, .notDetermined:
            speechRecognitionGranted = false
        @unknown default:
            speechRecognitionGranted = false
        }
    }

    func requestSpeechRecognition() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.speechRecognitionGranted = (status == .authorized)
            }
        }
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

    func openSpeechRecognitionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        }
    }

    var allGranted: Bool {
        microphoneGranted && accessibilityGranted && speechRecognitionGranted
    }
}
