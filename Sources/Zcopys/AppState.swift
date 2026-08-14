import Foundation
import AppKit
import Combine

enum PanelTab: Equatable, Hashable {
    case clipboard
    case usefulLinks
    case custom(UUID)
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
    @Published var linkEditorCategoryID: UUID?
    @Published var isCategoryEditorPresented = false
    @Published var categoryEditorName = ""
    @Published var editingCategoryID: UUID?

    let clipboardStore: ClipboardStore
    let usefulLinksStore: UsefulLinksStore
    let categoryStore: CategoryStore
    let syncEngine: CloudKitSyncEngine
    var panelController: ClipboardPanelController?
    /// App that was frontmost before the panel opened — paste target after selecting a card.
    private var previousFrontmostApp: NSRunningApplication?
    private var frontmostAppObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
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
        usefulLinksStorageURL: URL? = nil,
        categoriesStorageURL: URL? = nil,
        startMonitors: Bool = true,
        enableCloudKitSync: Bool? = nil
    ) {
        clipboardStore = ClipboardStore(storageURL: clipboardStorageURL)
        usefulLinksStore = UsefulLinksStore(storageURL: usefulLinksStorageURL)
        categoryStore = CategoryStore(storageURL: categoriesStorageURL)
        // Unit tests pass startMonitors: false — never construct CKContainer in XCTest.
        let cloudKitOn = enableCloudKitSync ?? startMonitors
        syncEngine = CloudKitSyncEngine(
            categoryStore: categoryStore,
            usefulLinksStore: usefulLinksStore,
            usesCloudKit: cloudKitOn
        )
        syncEngine.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        // Also refresh UI when category/link stores change from sync merge.
        categoryStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        usefulLinksStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        if startMonitors {
            isAccessibilityTrusted = hotkeyMonitor.isAccessibilityTrusted
            startMonitoring()
            observeFrontmostAppChanges()
            syncEngine.start()
        }
    }

    func startMonitoring() {
        clipboardMonitor.start()
        hotkeyMonitor.start()
    }

    func showHistoryWindow() {
        rememberPreviousFrontmostApp()
        // 延迟 0.1s 等 NSMenu 完全关闭后再显示面板
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.panelController?.showWindow()
            // Do not auto-focus search — that steals key focus from browser inputs
            // (App Store Connect) and breaks auto-paste.
            self.syncSelection()
        }
    }

    /// Call when search / link editor needs keyboard input.
    func requestTypingFocus() {
        panelController?.makeKeyForTyping()
    }

    func copyItemAndClose(_ item: ClipboardItem) {
        if clipboardStore.copyToClipboard(item) {
            let insertText: String? = (item.kind == .text || item.kind == .url || item.kind == .other)
                ? item.payload
                : nil
            closePanelAndPasteIntoPreviousApp(text: insertText)
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
        case .usefulLinks, .custom:
            guard let link = currentCategoryLinks().first(where: { $0.id == selectedItemID }) else { return }
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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(value, forType: .string) else {
            showFeedback("无法复制此记录")
            return
        }
        usefulLinksStore.markUsed(link)
        closePanelAndPasteIntoPreviousApp(text: value)
    }

    private func rememberPreviousFrontmostApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousFrontmostApp = front
        }
    }

    private func observeFrontmostAppChanges() {
        frontmostAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    self.previousFrontmostApp = app
                }
            }
        }
    }

    private func closePanelAndPasteIntoPreviousApp(text: String? = nil) {
        refreshAccessibilityTrust()
        let target = previousFrontmostApp
        let strategy = PasteboardPaster.preferredStrategy(for: target)
        panelController?.closeWindow()

        // Do not NSApp.hide / prompt Accessibility here — that dismisses the
        // system permission sheet and makes the toggle appear to "turn off".
        guard isAccessibilityTrusted else {
            activatePasteTarget(target)
            showFeedback("已复制，请按 ⌘V 粘贴")
            return
        }

        // Browsers need a slightly longer settle time after focus returns;
        // native fields can paste sooner.
        let activateDelay: TimeInterval = strategy == .keystrokeOnly ? 0.12 : 0.08
        let pasteDelay: TimeInterval = strategy == .keystrokeOnly ? 0.28 : 0.18

        DispatchQueue.main.asyncAfter(deadline: .now() + activateDelay) { [weak self] in
            guard let self else { return }
            self.activatePasteTarget(target)
            DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
                _ = PasteboardPaster.paste(
                    textFallbackToKeystroke: text,
                    into: target,
                    strategy: strategy
                )
            }
        }
    }

    private func activatePasteTarget(_ target: NSRunningApplication?) {
        guard let target, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        // Re-activating an already-frontmost Chromium app can drop the field's
        // first responder — skip when we never stole focus (nonactivating panel).
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
            return
        }
        target.activate(options: [.activateAllWindows])
    }

    func addClipboardItemToUsefulLinks(_ item: ClipboardItem) {
        addClipboardItem(item, toCategoryId: nil)
    }

    func addClipboardItem(_ item: ClipboardItem, toCategoryId categoryId: UUID?) {
        usefulLinksStore.add(
            title: String(item.value.prefix(80)),
            urlOrText: item.payload,
            categoryId: categoryId
        )
        if let categoryId,
           let name = categoryStore.categories.first(where: { $0.id == categoryId })?.name {
            showFeedback("已加入 \(name)")
        } else {
            showFeedback("已加入 Useful Links")
        }
    }

    // MARK: - Link editor

    func beginAddUsefulLink() {
        beginAddLink(categoryId: currentLinkCategoryID)
    }

    func beginAddLink(categoryId: UUID?) {
        editingLinkID = nil
        linkEditorCategoryID = categoryId
        linkEditorTitle = ""
        linkEditorBody = ""
        isCategoryEditorPresented = false
        isLinkEditorPresented = true
        requestTypingFocus()
    }

    func beginEditUsefulLink(_ link: UsefulLink) {
        editingLinkID = link.id
        linkEditorCategoryID = link.categoryId
        linkEditorTitle = link.title
        linkEditorBody = link.urlOrText
        isCategoryEditorPresented = false
        isLinkEditorPresented = true
        requestTypingFocus()
    }

    func saveLinkEditor() {
        let didSave: Bool
        if let editingLinkID,
           let link = usefulLinksStore.items.first(where: { $0.id == editingLinkID }) {
            didSave = usefulLinksStore.update(link, title: linkEditorTitle, urlOrText: linkEditorBody)
        } else {
            didSave = usefulLinksStore.add(
                title: linkEditorTitle,
                urlOrText: linkEditorBody,
                categoryId: linkEditorCategoryID
            )
        }
        guard didSave else { return }
        cancelLinkEditor()
        syncSelection()
    }

    func cancelLinkEditor() {
        isLinkEditorPresented = false
        editingLinkID = nil
        linkEditorCategoryID = nil
        linkEditorTitle = ""
        linkEditorBody = ""
        panelController?.refreshTapFlags()
    }

    // MARK: - Category editor

    func beginAddCategory() {
        editingCategoryID = nil
        categoryEditorName = ""
        isLinkEditorPresented = false
        isCategoryEditorPresented = true
        requestTypingFocus()
    }

    func beginRenameCategory(_ category: PanelCategory) {
        editingCategoryID = category.id
        categoryEditorName = category.name
        isLinkEditorPresented = false
        isCategoryEditorPresented = true
        requestTypingFocus()
    }

    func saveCategoryEditor() {
        if let editingCategoryID,
           let category = categoryStore.categories.first(where: { $0.id == editingCategoryID }) {
            guard categoryStore.rename(category, to: categoryEditorName) else { return }
        } else {
            guard let created = categoryStore.add(name: categoryEditorName) else { return }
            selectedTab = .custom(created.id)
        }
        cancelCategoryEditor()
        syncSelection()
    }

    func cancelCategoryEditor() {
        isCategoryEditorPresented = false
        editingCategoryID = nil
        categoryEditorName = ""
        panelController?.refreshTapFlags()
    }

    func deleteCategory(_ category: PanelCategory) {
        usefulLinksStore.deleteAll(in: category.id)
        categoryStore.delete(category)
        if case .custom(let id) = selectedTab, id == category.id {
            selectedTab = .usefulLinks
        }
        syncSelection()
        showFeedback("已删除分类")
    }

    func moveCategory(_ category: PanelCategory, left: Bool) {
        categoryStore.move(category, left: left)
    }

    func clearCurrentTab() {
        switch selectedTab {
        case .clipboard:
            clearHistory()
        case .usefulLinks:
            usefulLinksStore.clear(categoryId: nil)
            selectedItemID = nil
        case .custom(let id):
            usefulLinksStore.clear(categoryId: id)
            selectedItemID = nil
        }
    }

    func collapseSearchIfNeeded() {
        if searchText.isEmpty {
            isSearchExpanded = false
            panelController?.refreshTapFlags()
        }
    }

    func dismissPanel() {
        isCategoryEditorPresented = false
        editingCategoryID = nil
        categoryEditorName = ""
        isLinkEditorPresented = false
        editingLinkID = nil
        linkEditorCategoryID = nil
        linkEditorTitle = ""
        linkEditorBody = ""
        clearSearch()
        panelController?.closeWindow()
    }

    func clearSearch() {
        searchText = ""
        isSearchExpanded = false
        selectedItemID = activeItemIDs().first
        panelController?.refreshTapFlags()
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

    var linkEditorHeading: String {
        if editingLinkID != nil {
            return currentLinkCategoryID == nil ? "Edit Useful Link" : "Edit Item"
        }
        return currentLinkCategoryID == nil ? "Add Useful Link" : "Add Item"
    }

    var categoryEditorHeading: String {
        editingCategoryID == nil ? "New Category" : "Rename Category"
    }

    func currentCategoryLinks() -> [UsefulLink] {
        usefulLinksStore.filteredItems(matching: searchText, categoryId: currentLinkCategoryID)
    }

    private var currentLinkCategoryID: UUID? {
        switch selectedTab {
        case .usefulLinks:
            return nil
        case .custom(let id):
            return id
        case .clipboard:
            return nil
        }
    }

    private func activeItemIDs() -> [UUID] {
        switch selectedTab {
        case .clipboard:
            return clipboardStore.filteredItems(matching: searchText).map(\.id)
        case .usefulLinks, .custom:
            return currentCategoryLinks().map(\.id)
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
