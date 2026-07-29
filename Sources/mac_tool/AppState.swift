import Foundation
import AppKit

enum PanelTab {
    case clipboard
    case usefulLinks
}

@MainActor
final class AppState: ObservableObject {
    @Published var searchText = ""
    @Published var shouldFocusSearch = false
    @Published var selectedItemID: UUID?
    @Published var feedbackMessage: String?
    @Published private(set) var isAccessibilityTrusted = false
    @Published var selectedTab: PanelTab = .clipboard
    @Published var isSearchExpanded = false
    @Published var isLinkEditorPresented = false
    @Published var linkEditorTitle = ""
    @Published var linkEditorBody = ""
    @Published var editingLinkID: UsefulLink.ID?

    let clipboardStore: ClipboardStore
    let usefulLinksStore: UsefulLinksStore
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

    init(
        clipboardStorageURL: URL? = nil,
        usefulLinksStorageURL: URL? = nil
    ) {
        clipboardStore = ClipboardStore(storageURL: clipboardStorageURL)
        usefulLinksStore = UsefulLinksStore(storageURL: usefulLinksStorageURL)
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

    func moveSelection(left: Bool) {
        let ids = activeItemIDs()
        guard !ids.isEmpty else {
            selectedItemID = nil
            return
        }
        let currentIndex = ids.firstIndex(where: { $0 == selectedItemID })
        let nextIndex: Int
        if let currentIndex {
            nextIndex = left ? max(0, currentIndex - 1) : min(ids.count - 1, currentIndex + 1)
        } else {
            nextIndex = left ? ids.count - 1 : 0
        }
        selectedItemID = ids[nextIndex]
    }

    func activateSelectedItem() {
        switch selectedTab {
        case .clipboard:
            guard let item = clipboardStore.filteredItems(matching: searchText)
                .first(where: { $0.id == selectedItemID }) else { return }
            activateClipboardItem(item)
        case .usefulLinks:
            guard let link = usefulLinksStore.filteredItems(matching: searchText)
                .first(where: { $0.id == selectedItemID }) else { return }
            activateUsefulLink(link)
        }
    }

    func activateClipboardItem(_ item: ClipboardItem) {
        copyItemAndClose(item)
    }

    func activateUsefulLink(_ link: UsefulLink) {
        let value = link.urlOrText
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            usefulLinksStore.markUsed(link)
            NSWorkspace.shared.open(url)
            panelController?.closeWindow()
            return
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(value, forType: .string) else {
            showFeedback("无法复制此记录")
            return
        }
        usefulLinksStore.markUsed(link)
        panelController?.closeWindow()
    }

    func addClipboardItemToUsefulLinks(_ item: ClipboardItem) {
        usefulLinksStore.add(title: String(item.value.prefix(80)), urlOrText: item.payload)
        showFeedback("已加入 Useful Links")
    }

    func beginAddUsefulLink() {
        editingLinkID = nil
        linkEditorTitle = ""
        linkEditorBody = ""
        isLinkEditorPresented = true
    }

    func beginEditUsefulLink(_ link: UsefulLink) {
        editingLinkID = link.id
        linkEditorTitle = link.title
        linkEditorBody = link.urlOrText
        isLinkEditorPresented = true
    }

    func saveLinkEditor() {
        let didSave: Bool
        if let editingLinkID,
           let link = usefulLinksStore.items.first(where: { $0.id == editingLinkID }) {
            didSave = usefulLinksStore.update(link, title: linkEditorTitle, urlOrText: linkEditorBody)
        } else {
            didSave = usefulLinksStore.add(title: linkEditorTitle, urlOrText: linkEditorBody)
        }
        guard didSave else { return }
        cancelLinkEditor()
        syncSelection()
    }

    func cancelLinkEditor() {
        isLinkEditorPresented = false
        editingLinkID = nil
        linkEditorTitle = ""
        linkEditorBody = ""
    }

    func clearCurrentTab() {
        switch selectedTab {
        case .clipboard:
            clearHistory()
        case .usefulLinks:
            usefulLinksStore.clear()
            selectedItemID = nil
        }
    }

    func collapseSearchIfNeeded() {
        if searchText.isEmpty {
            isSearchExpanded = false
        }
    }

    func clearSearch() {
        searchText = ""
        selectedItemID = activeItemIDs().first
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
        let ids = activeItemIDs()
        if let selectedItemID, ids.contains(selectedItemID) { return }
        selectedItemID = ids.first
    }

    var selectedItem: ClipboardItem? {
        clipboardStore.filteredItems(matching: searchText).first { $0.id == selectedItemID }
    }

    private func activeItemIDs() -> [UUID] {
        switch selectedTab {
        case .clipboard:
            return clipboardStore.filteredItems(matching: searchText).map(\.id)
        case .usefulLinks:
            return usefulLinksStore.filteredItems(matching: searchText).map(\.id)
        }
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
