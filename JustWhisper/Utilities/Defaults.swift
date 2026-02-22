import Foundation

enum Defaults {
    static let selectedLocaleIdentifier = "selectedLocaleIdentifier"
    static let hotkeyMode = "hotkeyMode"
    static let selectedInputDeviceUID = "selectedInputDeviceUID"
    static let showOverlay = "showOverlay"
    static let autoInsert = "autoInsert"
    static let launchAtLogin = "launchAtLogin"
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
}
