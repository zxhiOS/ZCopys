import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum PasteboardPaster {
    /// Bundle IDs where AX text writes often report success but never update the
    /// real web/React field (Chrome, Safari, App Store Connect in-browser, etc.).
    private static let keystrokeOnlyBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "company.thebrowser.Browser", // Arc
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "app.zen-browser.zen",
        "com.apple.WebKit.WebContent"
    ]

    enum Strategy {
        /// Try Accessibility insert first, then ⌘V.
        case accessibilityThenKeystroke
        /// Only simulate ⌘V (required for most browser web forms).
        case keystrokeOnly
    }

    /// Insert into the focused field. Prefer keystroke when pasteboard is already set
    /// and the target is a browser — AX writes are unreliable for App Store Connect etc.
    @discardableResult
    static func paste(
        textFallbackToKeystroke text: String? = nil,
        into target: NSRunningApplication? = nil,
        strategy: Strategy? = nil
    ) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let resolved = strategy ?? preferredStrategy(for: target)

        if resolved == .accessibilityThenKeystroke,
           let text,
           insertTextViaAccessibility(text) {
            return true
        }

        simulateCommandV()
        return true
    }

    static func preferredStrategy(for target: NSRunningApplication?) -> Strategy {
        guard let bundleID = target?.bundleIdentifier else {
            return .accessibilityThenKeystroke
        }
        if keystrokeOnlyBundleIDs.contains(bundleID) {
            return .keystrokeOnly
        }
        // Chromium / Electron helpers often use com.*.helper — treat as keystroke-only
        // when the localized name looks like a browser.
        let name = (target?.localizedName ?? "").lowercased()
        if name.contains("chrome")
            || name.contains("safari")
            || name.contains("firefox")
            || name.contains("edge")
            || name.contains("brave")
            || name.contains("arc")
            || name.contains("opera") {
            return .keystrokeOnly
        }
        return .accessibilityThenKeystroke
    }

    /// Prefer setting AXSelectedText on the focused element (works in most native text fields).
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

        // Never trust AX writes on web areas — they often succeed without changing the DOM.
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           let roleString = role as? String,
           roleString == "AXWebArea" {
            return false
        }

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
            usleep(12_000)
        }
    }
}
