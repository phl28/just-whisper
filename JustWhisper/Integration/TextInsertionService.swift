import AppKit
import OSLog

@MainActor
final class TextInsertionService {

    func insertText(_ text: String) {
        guard !text.isEmpty else { return }

        if insertViaAccessibility(text) {
            Logger.integration.debug("Inserted text via Accessibility API")
            return
        }

        if insertViaPasteboard(text) {
            Logger.integration.debug("Inserted text via pasteboard")
            return
        }

        Logger.integration.warning("All text insertion methods failed")
    }

    private func insertViaAccessibility(_ text: String) -> Bool {
        let systemElement = AXUIElementCreateSystemWide()

        var focusedElement: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusedResult == .success, let element = focusedElement else {
            return false
        }

        let axElement = element as! AXUIElement

        var currentValue: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            &currentValue
        )

        var selectedRange: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        if valueResult == .success, rangeResult == .success,
           let currentString = currentValue as? String,
           let rangeValue = selectedRange {
            var range = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
                let nsString = currentString as NSString
                let insertionPoint = range.location
                let newString = nsString.replacingCharacters(
                    in: NSRange(location: insertionPoint, length: range.length),
                    with: text
                )
                let setResult = AXUIElementSetAttributeValue(
                    axElement,
                    kAXValueAttribute as CFString,
                    newString as CFTypeRef
                )
                if setResult == .success {
                    var newRange = CFRange(location: insertionPoint + text.count, length: 0)
                    if let newRangeValue = AXValueCreate(.cfRange, &newRange) {
                        AXUIElementSetAttributeValue(
                            axElement,
                            kAXSelectedTextRangeAttribute as CFString,
                            newRangeValue
                        )
                    }
                    return true
                }
            }
        }

        let directSet = AXUIElementSetAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if directSet == .success {
            return true
        }

        return false
    }

    private func insertViaPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pasteboard.clearContents()
            if let previous = previousContents {
                pasteboard.setString(previous, forType: .string)
            }
        }

        return true
    }
}
