import AppKit
import ApplicationServices
import Foundation

final class HotkeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onHotkey: @MainActor () -> Void

    init(onHotkey: @escaping @MainActor () -> Void) {
        self.onHotkey = onHotkey
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        // 先尝试弹出系统授权弹窗
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // 同时打开系统设置 → 辅助功能面板（作为后备）
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func start() {
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.command, .shift], event.keyCode == 9 else { return }
        Task { @MainActor [weak self] in
            self?.onHotkey()
        }
    }
}
