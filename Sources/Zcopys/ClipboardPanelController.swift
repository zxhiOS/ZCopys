import AppKit
import CoreGraphics
import SwiftUI

/// Borderless floating panel that can still become key so TextFields accept typing.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shared state for the CGEvent tap callback (runs off the main actor).
private final class PanelNavigationTapState: @unchecked Sendable {
    weak var controller: ClipboardPanelController?
    /// Panel is open and should intercept ←/→/Tab/Return/Esc.
    var interceptNavigation = false
    /// Search field / link editor owns typing — let keys through.
    var allowTextInput = false
}

@MainActor
final class ClipboardPanelController {
    private let panel: KeyablePanel
    private var localKeyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var localOutsideClickMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private unowned let appState: AppState
    private let tapState = PanelNavigationTapState()

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
        tapState.controller = self
        installLocalKeyMonitor()
        installNavigationEventTap()
    }

    var isVisible: Bool {
        panel.isVisible
    }

    var panelFrame: NSRect {
        panel.frame
    }

    func showWindow() {
        layoutPanelAtBottomFullWidth()
        // Do not activate / steal key focus — target app (Safari/Chrome) must keep
        // the text field focused for paste into App Store Connect etc.
        panel.orderFrontRegardless()
        refreshTapFlags()
        installOutsideClickMonitor()
    }

    /// Become key only when the user needs to type (search / link editor).
    func makeKeyForTyping() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        refreshTapFlags()
    }

    func closeWindow() {
        removeOutsideClickMonitor()
        panel.orderOut(nil)
        refreshTapFlags()
    }

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
    }

    /// Update event-tap flags after UI mode changes (search / editor).
    func refreshTapFlags() {
        let visible = panel.isVisible
        tapState.interceptNavigation = visible
        tapState.allowTextInput = visible && (isTextInputActive || isTextCompositionActive)
    }

    // MARK: - Click outside to dismiss

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePossibleOutsideClick()
            }
        }

        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            Task { @MainActor in
                self?.handlePossibleOutsideClick()
            }
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }
    }

    private func handlePossibleOutsideClick() {
        guard panel.isVisible else { return }
        let point = NSEvent.mouseLocation
        if panel.frame.contains(point) { return }
        if isClickInStatusItemArea(point) { return }
        appState.dismissPanel()
    }

    private func isClickInStatusItemArea(_ point: NSPoint) -> Bool {
        for window in NSApp.windows {
            let name = NSStringFromClass(type(of: window))
            if name.contains("NSStatusBar") || name.contains("StatusItem") {
                if window.frame.contains(point) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Local monitor (when panel is key, e.g. typing in search)

    private func installLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.panel.isVisible else { return event }
            return self.handleNavigationKey(event) ? nil : event
        }
    }

    /// Returns true when the key was handled (and should be swallowed).
    @discardableResult
    func handleNavigationKey(_ event: NSEvent) -> Bool {
        refreshTapFlags()

        if isTextInputActive {
            // While typing in search / editor, only handle Esc specially.
            if event.keyCode == 53 {
                if appState.isCategoryEditorPresented {
                    appState.cancelCategoryEditor()
                    refreshTapFlags()
                    return true
                }
                if appState.isLinkEditorPresented {
                    appState.cancelLinkEditor()
                    refreshTapFlags()
                    return true
                }
                if appState.isSearchExpanded || !appState.searchText.isEmpty {
                    appState.searchText = ""
                    appState.isSearchExpanded = false
                    appState.syncSelection()
                    refreshTapFlags()
                    return true
                }
                appState.clearSearch()
                closeWindow()
                return true
            }
            return false
        }

        if isTextCompositionActive {
            return false
        }

        // Link / category editor owns left/right/Tab/Return; only Esc is intercepted.
        if appState.isLinkEditorPresented || appState.isCategoryEditorPresented {
            if event.keyCode == 53 {
                if appState.isCategoryEditorPresented {
                    appState.cancelCategoryEditor()
                } else {
                    appState.cancelLinkEditor()
                }
                refreshTapFlags()
                return true
            }
            return false
        }

        switch event.keyCode {
        case 123: // left
            appState.moveSelection(left: true)
            return true
        case 124: // right
            appState.moveSelection(left: false)
            return true
        case 48: // tab
            appState.moveSelection(left: event.modifierFlags.contains(.shift))
            return true
        case 36, 76: // return / keypad enter
            appState.activateSelectedItem()
            return true
        case 53: // escape
            if appState.isSearchExpanded || !appState.searchText.isEmpty {
                appState.searchText = ""
                appState.isSearchExpanded = false
                appState.syncSelection()
                refreshTapFlags()
                return true
            }
            appState.clearSearch()
            closeWindow()
            return true
        default:
            return false
        }
    }

    // MARK: - Global event tap (panel nonactivating — still capture ←/→)

    private func installNavigationEventTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(tapState).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let state = Unmanaged<PanelNavigationTapState>.fromOpaque(userInfo).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let controller = state.controller {
                        Task { @MainActor in
                            controller.reenableEventTap()
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard type == .keyDown, state.interceptNavigation, !state.allowTextInput else {
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let handledCodes: Set<Int64> = [123, 124, 48, 36, 76, 53]
                guard handledCodes.contains(keyCode) else {
                    return Unmanaged.passUnretained(event)
                }

                // Ignore when command/option/control held (except shift+tab).
                let flags = event.flags
                let hasCmd = flags.contains(.maskCommand)
                let hasAlt = flags.contains(.maskAlternate)
                let hasCtrl = flags.contains(.maskControl)
                if hasCmd || hasAlt || hasCtrl {
                    return Unmanaged.passUnretained(event)
                }

                guard let controller = state.controller else {
                    return Unmanaged.passUnretained(event)
                }

                let shift = flags.contains(.maskShift)
                Task { @MainActor in
                    controller.handleNavigationKeyCode(UInt16(keyCode), shift: shift)
                }
                // Swallow so the frontmost browser field doesn't also move the caret.
                return nil
            },
            userInfo: userInfo
        ) else {
            print("ClipboardPanelController: CGEvent tap unavailable — ←/→ need Accessibility")
            return
        }

        eventTap = tap
        eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let eventTapSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func reenableEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    fileprivate func handleNavigationKeyCode(_ keyCode: UInt16, shift: Bool) {
        switch keyCode {
        case 123:
            appState.moveSelection(left: true)
        case 124:
            appState.moveSelection(left: false)
        case 48:
            appState.moveSelection(left: shift)
        case 36, 76:
            appState.activateSelectedItem()
        case 53:
            if appState.isSearchExpanded || !appState.searchText.isEmpty {
                appState.searchText = ""
                appState.isSearchExpanded = false
                appState.syncSelection()
                refreshTapFlags()
            } else if appState.isCategoryEditorPresented {
                appState.cancelCategoryEditor()
                refreshTapFlags()
            } else if appState.isLinkEditorPresented {
                appState.cancelLinkEditor()
                refreshTapFlags()
            } else {
                appState.clearSearch()
                closeWindow()
            }
        default:
            break
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
        if appState.isLinkEditorPresented || appState.isCategoryEditorPresented { return true }
        if appState.isSearchExpanded && panel.isKeyWindow { return true }
        if let textView = panel.firstResponder as? NSTextView, textView.isEditable {
            return true
        }
        return panel.firstResponder is NSTextField
    }
}
