import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var appState: AppState!
    var panelController: ClipboardPanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
        panelController = ClipboardPanelController(appState: appState)
        appState.panelController = panelController

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.statusBarImage()
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }

        // 启动测试数据
        appState.clipboardStore.addText("启动成功 ✓ — 复制文字即可记录")

        // 用户在系统设置里授权后，刷新状态（不在启动时弹权限，避免反复打断）
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.appState.refreshAccessibilityTrust()
            }
        }
    }

    @objc private func statusBarButtonClicked() {
        let menu = NSMenu()

        let historyItem = NSMenuItem(
            title: "打开历史",
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        historyItem.target = self
        menu.addItem(historyItem)

        let clearItem = NSMenuItem(
            title: "清空记录",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)

        if !appState.isAccessibilityTrusted {
            menu.addItem(.separator())

            let hintItem = NSMenuItem(
                title: "全局快捷键需要辅助功能权限",
                action: nil,
                keyEquivalent: ""
            )
            hintItem.isEnabled = false
            menu.addItem(hintItem)

            let authItem = NSMenuItem(
                title: "授权全局快捷键",
                action: #selector(requestAccessibility),
                keyEquivalent: ""
            )
            authItem.target = self
            menu.addItem(authItem)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(terminateApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openHistory() {
        appState.showHistoryWindow()
    }

    @objc private func clearHistory() {
        appState.clearHistory()
    }

    @objc private func requestAccessibility() {
        appState.requestAccessibilityPermission()
    }

    @objc private func terminateApp() {
        NSApplication.shared.terminate(nil)
    }

    private static func statusBarImage() -> NSImage {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: "StatusBarIcon", withExtension: "png"),
            Bundle.main.url(forResource: "StatusBarIcon", withExtension: "png"),
            Bundle.main.resourceURL?.appendingPathComponent("StatusBarIcon.png")
        ]

        for case let url? in candidates {
            if let image = NSImage(contentsOf: url) {
                // Colored white-bg / gray-glyph asset — not a template
                image.isTemplate = false
                image.size = NSSize(width: 18, height: 18)
                return image
            }
        }

        let fallback = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "Zcopys"
        )!
        fallback.isTemplate = true
        return fallback
    }
}

@main
struct ZcopysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
