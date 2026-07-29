import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum PasteboardPaster {
    /// Insert text into the focused UI element when possible.
    /// Falls back to simulating ⌘V. Requires Accessibility permission.
    @discardableResult
    static func paste(textFallbackToKeystroke text: String? = nil) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        if let text, insertTextViaAccessibility(text) {
            return true
        }

        simulateCommandV()
        return true
    }

    /// Prefer setting AXSelectedText on the focused element (works in most text fields).
    static func insertTextViaAccessibility(_ string: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard copyResult == .success, let focused else { return false }

        let element = focused as! AXUIElement

        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
           settable.boolValue {
            let status = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                string as CFTypeRef
            )
            if status == .success { return true }
        }

        // Some fields expose AXValue instead
        settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            var current: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &current) == .success,
               let existing = current as? String {
                // Replace selection isn't available — append as last resort only when empty
                if existing.isEmpty {
                    return AXUIElementSetAttributeValue(
                        element,
                        kAXValueAttribute as CFString,
                        string as CFTypeRef
                    ) == .success
                }
            }
        }

        return false
    }

    /// Full ⌘↓ V↓ V↑ ⌘↑ sequence — more reliable than flags-only key events.
    static func simulateCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0

        let cmd: CGKeyCode = CGKeyCode(kVK_Command)
        let v: CGKeyCode = CGKeyCode(kVK_ANSI_V)

        let events: [(CGKeyCode, Bool, CGEventFlags)] = [
            (cmd, true, []),
            (v, true, .maskCommand),
            (v, false, .maskCommand),
            (cmd, false, [])
        ]

        for (keyCode, keyDown, flags) in events {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
                continue
            }
            event.flags = flags
            event.post(tap: .cghidEventTap)
            // Tiny gap helps some apps register the chord
            usleep(8_000)
        }
    }
}
