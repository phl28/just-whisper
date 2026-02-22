import Foundation

enum Defaults {
    static let selectedLocaleIdentifier = "selectedLocaleIdentifier"
    static let hotkeyMode = "hotkeyMode"
    static let selectedInputDeviceUID = "selectedInputDeviceUID"
    static let showOverlay = "showOverlay"
    static let autoInsert = "autoInsert"
    static let launchAtLogin = "launchAtLogin"
    static let enginePreference = "enginePreference"
    static let silenceTimeoutSeconds = "silenceTimeoutSeconds"
    static let whisperKitModel = "whisperKitModel"
}

enum EnginePreference: String, CaseIterable, Identifiable {
    case auto
    case apple
    case whisperKit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .apple: "Apple Speech"
        case .whisperKit: "WhisperKit"
        }
    }
}

extension UserDefaults {
    var selectedLocaleIdentifier: String {
        get { string(forKey: Defaults.selectedLocaleIdentifier) ?? Locale.current.identifier }
        set { set(newValue, forKey: Defaults.selectedLocaleIdentifier) }
    }

    var hotkeyMode: String {
        get { string(forKey: Defaults.hotkeyMode) ?? "toggle" }
        set { set(newValue, forKey: Defaults.hotkeyMode) }
    }

    var selectedInputDeviceUID: String? {
        get { string(forKey: Defaults.selectedInputDeviceUID) }
        set { set(newValue, forKey: Defaults.selectedInputDeviceUID) }
    }

    var showOverlay: Bool {
        get {
            if object(forKey: Defaults.showOverlay) == nil { return true }
            return bool(forKey: Defaults.showOverlay)
        }
        set { set(newValue, forKey: Defaults.showOverlay) }
    }

    var autoInsert: Bool {
        get {
            if object(forKey: Defaults.autoInsert) == nil { return true }
            return bool(forKey: Defaults.autoInsert)
        }
        set { set(newValue, forKey: Defaults.autoInsert) }
    }

    var launchAtLogin: Bool {
        get { bool(forKey: Defaults.launchAtLogin) }
        set { set(newValue, forKey: Defaults.launchAtLogin) }
    }

    var enginePreference: EnginePreference {
        get {
            guard let raw = string(forKey: Defaults.enginePreference),
                  let pref = EnginePreference(rawValue: raw)
            else { return .auto }
            return pref
        }
        set { set(newValue.rawValue, forKey: Defaults.enginePreference) }
    }

    var silenceTimeoutSeconds: TimeInterval {
        get {
            let val = double(forKey: Defaults.silenceTimeoutSeconds)
            return val > 0 ? val : 30
        }
        set { set(newValue, forKey: Defaults.silenceTimeoutSeconds) }
    }

    var whisperKitModel: String {
        get { string(forKey: Defaults.whisperKitModel) ?? "base" }
        set { set(newValue, forKey: Defaults.whisperKitModel) }
    }
}
