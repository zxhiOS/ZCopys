import AppKit
import SwiftUI

@MainActor
final class ClipboardPanelController {
    private let panel: NSPanel
    private var keyMonitor: Any?
    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        let rootView = ContentView()
            .environmentObject(appState)

        let hostingController = NSHostingController(rootView: rootView)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        installKeyMonitor()
    }

    func showWindow() {
        if !panel.isVisible {
            centerPanel()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func closeWindow() {
        panel.orderOut(nil)
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.panel.isVisible else { return event }

            if self.isTextCompositionActive {
                return event
            }

            switch event.keyCode {
            case 123: // left
                self.appState.moveSelection(left: true)
                return nil
            case 124: // right
                self.appState.moveSelection(left: false)
                return nil
            case 48: // tab
                self.appState.moveSelection(left: event.modifierFlags.contains(.shift))
                return nil
            case 36: // return
                self.appState.activateSelectedItem()
                return nil
            case 53: // escape
                self.appState.clearSearch()
                self.closeWindow()
                return nil
            default:
                return event
            }
        }
    }

    private func centerPanel() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            return
        }
        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 60
        )
        panel.setFrameOrigin(origin)
    }

    private var isTextCompositionActive: Bool {
        (panel.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }
}
