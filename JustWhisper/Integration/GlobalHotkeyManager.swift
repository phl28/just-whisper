import Carbon
import CoreGraphics
import OSLog

@Observable
@MainActor
final class GlobalHotkeyManager {
    enum Mode: String, CaseIterable {
        case toggle
        case holdToTalk
    }

    var mode: Mode = .toggle
    var onActivate: (() -> Void)?
    var onDeactivate: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var callbackContext: HotkeyCallbackContext?
    private var isActive = false
    private(set) var isRegistered = false

    private var lastOptionPressTime: TimeInterval = 0
    private static let doubleTapThreshold: TimeInterval = 0.35
    private var rightOptionHeld = false

    func register() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let context = HotkeyCallbackContext(manager: self)
        let unmanagedContext = Unmanaged.passRetained(context)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: globalHotkeyCallback,
            userInfo: unmanagedContext.toOpaque()
        ) else {
            unmanagedContext.release()
            Logger.integration.error("Failed to create event tap. Check Accessibility permissions.")
            return
        }

        context.tap = tap
        callbackContext = context
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        isRegistered = true
        Logger.integration.info("Global hotkey registered (double-tap right Option)")
    }

    func unregister() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        isRegistered = false
        Logger.integration.info("Global hotkey unregistered")
    }

    nonisolated func handleFlagsChanged(_ event: CGEvent) {
        let flags = event.flags
        let isRightOption = flags.contains(.maskAlternate) &&
            event.getIntegerValueField(.keyboardEventKeycode) == 61

        let now = ProcessInfo.processInfo.systemUptime

        Task { @MainActor in
            if isRightOption && !self.rightOptionHeld {
                self.rightOptionHeld = true

                if self.mode == .holdToTalk && !self.isActive {
                    self.activate()
                }

                let elapsed = now - self.lastOptionPressTime
                if elapsed < Self.doubleTapThreshold && self.mode == .toggle {
                    if self.isActive {
                        self.deactivate()
                    } else {
                        self.activate()
                    }
                }
                self.lastOptionPressTime = now
            } else if !flags.contains(.maskAlternate) && self.rightOptionHeld {
                self.rightOptionHeld = false

                if self.mode == .holdToTalk && self.isActive {
                    self.deactivate()
                }
            }
        }
    }

    private func activate() {
        guard !isActive else { return }
        isActive = true
        onActivate?()
        Logger.integration.debug("Hotkey activated")
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        onDeactivate?()
        Logger.integration.debug("Hotkey deactivated")
    }
}

private final class HotkeyCallbackContext {
    weak var manager: GlobalHotkeyManager?
    var tap: CFMachPort?

    init(manager: GlobalHotkeyManager) {
        self.manager = manager
    }
}

private func globalHotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }

    let context = Unmanaged<HotkeyCallbackContext>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = context.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    if type == .flagsChanged, let manager = context.manager {
        manager.handleFlagsChanged(event)
    }

    return Unmanaged.passRetained(event)
}
