import AppKit
import SwiftUI

/// Borderless floating panel that can still become key so TextFields accept typing.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClipboardPanelController {
    private let panel: KeyablePanel
    private var keyMonitor: Any?
    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        let rootView = ContentView()
            .environmentObject(appState)

        let hostingController = NSHostingController(rootView: rootView)
        // nonactivatingPanel keeps the previous app's focused field (e.g. App Store
        // Connect web inputs) so ⌘V still lands in the right place after a click.
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 400),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        installKeyMonitor()
    }

    func showWindow() {
        layoutPanelAtBottomFullWidth()
        // Do not activate / steal key focus — target app (Safari/Chrome) must keep
        // the text field focused for paste into App Store Connect etc.
        panel.orderFrontRegardless()
    }

    /// Become key only when the user needs to type (search / link editor).
    func makeKeyForTyping() {
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

            if self.isTextInputActive {
                // While typing in search / editor, only handle Esc specially.
                if event.keyCode == 53 {
                    if self.appState.isLinkEditorPresented {
                        self.appState.cancelLinkEditor()
                        return nil
                    }
                    if self.appState.isSearchExpanded || !self.appState.searchText.isEmpty {
                        self.appState.searchText = ""
                        self.appState.isSearchExpanded = false
                        self.appState.syncSelection()
                        return nil
                    }
                    self.appState.clearSearch()
                    self.closeWindow()
                    return nil
                }
                return event
            }

            if self.isTextCompositionActive {
                return event
            }

            // Link editor owns left/right/Tab/Return; only Esc is intercepted.
            if self.appState.isLinkEditorPresented {
                if event.keyCode == 53 {
                    self.appState.cancelLinkEditor()
                    return nil
                }
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
                if self.appState.isSearchExpanded || !self.appState.searchText.isEmpty {
                    self.appState.searchText = ""
                    self.appState.isSearchExpanded = false
                    self.appState.syncSelection()
                    return nil
                }
                self.appState.clearSearch()
                self.closeWindow()
                return nil
            default:
                return event
            }
        }
    }

    private func layoutPanelAtBottomFullWidth() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            return
        }
        let visibleFrame = screen.visibleFrame
        let height: CGFloat = 400
        let frame = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: height
        )
        panel.setFrame(frame, display: true)
    }

    private var isTextCompositionActive: Bool {
        (panel.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    /// True when a text field / text view currently owns keyboard focus.
    private var isTextInputActive: Bool {
        if appState.isLinkEditorPresented { return true }
        if let textView = panel.firstResponder as? NSTextView, textView.isEditable {
            return true
        }
        return panel.firstResponder is NSTextField
    }
}
