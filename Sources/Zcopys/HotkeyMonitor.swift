import AppKit
import ApplicationServices
import Carbon
import Foundation

/// Registers ⌘⇧V as a system hotkey via Carbon (works without Accessibility).
/// Accessibility is still required for auto-paste into other apps.
final class HotkeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastFireAt: Date = .distantPast
    private let onHotkey: @MainActor () -> Void

    private static let hotKeySignature = OSType(0x4D544F4C) // 'MTOL'
    private static let hotKeyIDValue: UInt32 = 1

    /// Keep a stable C callback alive for Carbon's event handler.
    private static let carbonHandler: EventHandlerUPP = { (_, event, userData) -> OSStatus in
        guard let userData, let event else { return noErr }

        var hotKeyID = EventHotKeyID()
        let err = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard err == noErr,
              hotKeyID.signature == HotkeyMonitor.hotKeySignature,
              hotKeyID.id == HotkeyMonitor.hotKeyIDValue else {
            return noErr
        }

        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
        monitor.fire()
        return noErr
    }

    init(onHotkey: @escaping @MainActor () -> Void) {
        self.onHotkey = onHotkey
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        // Only open System Settings — do NOT call AXIsProcessTrustedWithOptions(prompt:true)
        // on every request. Repeated prompts + app hide/activate dismisses the dialog and
        // leaves Accessibility toggled off for ad-hoc / rebuilt binaries.
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                break
            }
        }
    }

    func start() {
        stop()
        registerCarbonHotKey()
        installEventMonitors()
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func registerCarbonHotKey() {
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyIDValue)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            // -9878 eventHotKeyExistsErr: another process already owns ⌘⇧V
            print("RegisterEventHotKey failed: \(status) — using NSEvent monitors as fallback")
            hotKeyRef = nil
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.carbonHandler,
            1,
            &eventType,
            userData,
            &eventHandler
        )
        if installStatus != noErr {
            print("InstallEventHandler failed: \(installStatus)")
        }
    }

    /// Fallback when Carbon is unavailable; also covers in-app keydowns.
    private func installEventMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleNSEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleNSEvent(event)
            return event
        }
    }

    private func handleNSEvent(_ event: NSEvent) {
        // Ignore Caps Lock / Fn; require exactly ⌘⇧ (no ⌥/⌃)
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == [.command, .shift], event.keyCode == UInt16(kVK_ANSI_V) else { return }
        fire()
    }

    private func fire() {
        let now = Date()
        // Carbon + NSEvent can both see the same keypress — debounce
        guard now.timeIntervalSince(lastFireAt) > 0.35 else { return }
        lastFireAt = now
        Task { @MainActor [weak self] in
            self?.onHotkey()
        }
    }
}
