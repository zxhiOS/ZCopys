import Foundation
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var searchText = ""
    @Published var shouldFocusSearch = false
    @Published var selectedItemID: ClipboardItem.ID?
    @Published var feedbackMessage: String?
    @Published private(set) var isAccessibilityTrusted = false

    let clipboardStore = ClipboardStore()
    var panelController: ClipboardPanelController?
    lazy var hotkeyMonitor = HotkeyMonitor { [weak self] in
        self?.showHistoryWindow()
    }
    lazy var clipboardMonitor = ClipboardMonitor(
        onTextCopy: { [weak self] text in
            self?.clipboardStore.addText(text)
        },
        onFileCopy: { [weak self] urls in
            self?.clipboardStore.addFileURLs(urls)
        },
        onImageCopy: { [weak self] image in
            self?.clipboardStore.addImage(image)
        }
    )

    init() {
        isAccessibilityTrusted = hotkeyMonitor.isAccessibilityTrusted
        startMonitoring()
    }

    func startMonitoring() {
        clipboardMonitor.start()
        hotkeyMonitor.start()
    }

    func showHistoryWindow() {
        // 延迟 0.1s 等 NSMenu 完全关闭后再显示面板
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.panelController?.showWindow()
            self.shouldFocusSearch = true
            self.syncSelection()
        }
    }

    func copyItemAndClose(_ item: ClipboardItem) {
        if clipboardStore.copyToClipboard(item) {
            panelController?.closeWindow()
        } else {
            showFeedback("无法复制此记录")
        }
    }

    func moveSelection(up: Bool) {
        let items = clipboardStore.filteredItems(matching: searchText)
        guard !items.isEmpty else {
            selectedItemID = nil
            return
        }

        let currentIndex = items.firstIndex { $0.id == selectedItemID }
        let nextIndex: Int
        if let currentIndex {
            nextIndex = up
                ? max(0, currentIndex - 1)
                : min(items.count - 1, currentIndex + 1)
        } else {
            nextIndex = up ? items.count - 1 : 0
        }
        selectedItemID = items[nextIndex].id
    }

    func copySelectedItemAndClose() {
        guard let selectedItem = selectedItem else { return }
        copyItemAndClose(selectedItem)
    }

    func clearSearch() {
        searchText = ""
        selectedItemID = clipboardStore.filteredItems(matching: searchText).first?.id
    }

    func delete(_ item: ClipboardItem) {
        clipboardStore.delete(item)
        syncSelection()
    }

    func clearHistory() {
        clipboardStore.clear()
        selectedItemID = nil
    }

    func refreshAccessibilityTrust() {
        isAccessibilityTrusted = hotkeyMonitor.isAccessibilityTrusted
    }

    func requestAccessibilityPermission() {
        hotkeyMonitor.requestAccessibilityPermission()
        refreshAccessibilityTrust()
    }

    func syncSelection() {
        let items = clipboardStore.filteredItems(matching: searchText)
        if let selectedItemID, items.contains(where: { $0.id == selectedItemID }) {
            return
        }
        selectedItemID = items.first?.id
    }

    var selectedItem: ClipboardItem? {
        clipboardStore.filteredItems(matching: searchText).first { $0.id == selectedItemID }
    }

    private func showFeedback(_ message: String) {
        feedbackMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if feedbackMessage == message {
                feedbackMessage = nil
            }
        }
    }
}
