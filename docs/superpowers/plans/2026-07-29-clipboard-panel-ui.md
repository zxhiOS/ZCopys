# Clipboard Panel UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the vertical clipboard popup with the glassmorphism horizontal-card UI and add an editable Useful Links tab (manual add + favorite from clipboard).

**Architecture:** Keep `ClipboardStore` as-is. Add `UsefulLink` + `UsefulLinksStore` for favorites. Extend `AppState` with tab/search-expand/selection for both lists. Rewrite `ContentView` as panel chrome + horizontal cards; resize panel and switch keyboard navigation to left/right in `ClipboardPanelController`.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, macOS 14+, XCTest, SPM executable target `mac_tool`

## Global Constraints

- Platform: macOS 14.0+
- Panel size: approximately 1100 × 420, corner radius ~28
- Useful Links persist to `~/Library/Application Support/mac_tool/useful-links.json`
- Title may be empty and defaults to truncated `urlOrText`; `urlOrText` is required
- On Clipboard tab, `+` is hidden
- Do not change packaging/notarization scripts
- Do not add auto-paste (⌘V simulation)
- Exclude `.build/` and `dist/` from commits

## File Structure

| File | Responsibility |
|------|----------------|
| `Sources/mac_tool/UsefulLink.swift` | Useful link model |
| `Sources/mac_tool/UsefulLinksStore.swift` | CRUD, pin, filter, JSON persistence |
| `Sources/mac_tool/CardPresentation.swift` | Shared relative time, header colors, char count, shell heuristic |
| `Sources/mac_tool/AppState.swift` | Tabs, search expand, both stores, selection, activate/add/edit |
| `Sources/mac_tool/ContentView.swift` | Glass chrome, tabs, horizontal cards, search expand, add/edit overlay |
| `Sources/mac_tool/ClipboardPanelController.swift` | Panel size 1100×420; left/right keys |
| `Tests/mac_toolTests/UsefulLinksStoreTests.swift` | Store unit tests |
| `Tests/mac_toolTests/CardPresentationTests.swift` | Color/heuristic/relative-time tests |
| `Tests/mac_toolTests/AppStateTests.swift` | Extend for tabs / useful links / horizontal selection |

---

### Task 0: Commit existing application baseline

**Files:**
- Create: `.gitignore`
- Add existing: `Package.swift`, `README.md`, `Scripts/`, `Sources/`, `Tests/` (not `.build/`, not `dist/`)

- [ ] **Step 1: Write `.gitignore`**

```gitignore
.build/
dist/
.DS_Store
*.xcodeproj
xcuserdata/
```

- [ ] **Step 2: Commit baseline**

```bash
git add .gitignore Package.swift README.md Scripts Sources Tests
git commit -m "$(cat <<'EOF'
chore: commit existing mac_tool clipboard app baseline

EOF
)"
```

Expected: commit succeeds; `git status` clean except maybe ignored paths.

---

### Task 1: UsefulLink model + UsefulLinksStore

**Files:**
- Create: `Sources/mac_tool/UsefulLink.swift`
- Create: `Sources/mac_tool/UsefulLinksStore.swift`
- Create: `Tests/mac_toolTests/UsefulLinksStoreTests.swift`

**Interfaces:**
- Produces:
  - `struct UsefulLink: Identifiable, Codable, Equatable` with `id`, `title`, `urlOrText`, `createdAt`, `lastUsedAt`, `isPinned`
  - `UsefulLinksStore` (`@MainActor`, `ObservableObject`):
    - `init(storageURL: URL? = nil)`
    - `var items: [UsefulLink] { get }`
    - `func add(title: String, urlOrText: String)`
    - `func update(_ link: UsefulLink, title: String, urlOrText: String)`
    - `func delete(_ link: UsefulLink)`
    - `func togglePin(_ link: UsefulLink)`
    - `func clear()`
    - `func markUsed(_ link: UsefulLink)`
    - `func filteredItems(matching query: String) -> [UsefulLink]`

- [ ] **Step 1: Write failing tests**

Create `Tests/mac_toolTests/UsefulLinksStoreTests.swift`:

```swift
import XCTest
@testable import mac_tool

@MainActor
final class UsefulLinksStoreTests: XCTestCase {
    func testAddInsertsLinkWithDefaultTitleFromBody() {
        withStore { store in
            store.add(title: "  ", urlOrText: "https://example.com/docs")
            XCTAssertEqual(store.items.count, 1)
            XCTAssertEqual(store.items[0].urlOrText, "https://example.com/docs")
            XCTAssertEqual(store.items[0].title, "https://example.com/docs")
        }
    }

    func testAddRejectsEmptyBody() {
        withStore { store in
            store.add(title: "Docs", urlOrText: "   ")
            XCTAssertTrue(store.items.isEmpty)
        }
    }

    func testDuplicateBodyUpdatesExistingInsteadOfInserting() {
        withStore { store in
            store.add(title: "A", urlOrText: "https://a.com")
            store.add(title: "B", urlOrText: "https://a.com")
            XCTAssertEqual(store.items.count, 1)
            XCTAssertEqual(store.items[0].title, "B")
        }
    }

    func testPinnedItemsRemainAhead() {
        withStore { store in
            store.add(title: "pinned", urlOrText: "p")
            store.togglePin(store.items[0])
            store.add(title: "recent", urlOrText: "r")
            XCTAssertEqual(store.items.map(\.title), ["pinned", "recent"])
        }
    }

    func testFilterMatchesTitleOrBody() {
        withStore { store in
            store.add(title: "GitLab", urlOrText: "https://git.example.com")
            store.add(title: "Notes", urlOrText: "hello world")
            XCTAssertEqual(store.filteredItems(matching: "git").map(\.title), ["GitLab"])
            XCTAssertEqual(store.filteredItems(matching: "hello").map(\.title), ["Notes"])
        }
    }

    func testClearRemovesAll() {
        withStore { store in
            store.add(title: "A", urlOrText: "a")
            store.clear()
            XCTAssertTrue(store.items.isEmpty)
        }
    }

    private func withStore(_ body: (UsefulLinksStore) -> Void) {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac_tool-links-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storageURL) }
        body(UsefulLinksStore(storageURL: storageURL))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UsefulLinksStoreTests`

Expected: FAIL (types not found / compile error)

- [ ] **Step 3: Implement model + store**

`Sources/mac_tool/UsefulLink.swift`:

```swift
import Foundation

struct UsefulLink: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var urlOrText: String
    let createdAt: Date
    var lastUsedAt: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        title: String,
        urlOrText: String,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.urlOrText = urlOrText
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt ?? createdAt
        self.isPinned = isPinned
    }
}
```

`Sources/mac_tool/UsefulLinksStore.swift`:

```swift
import Foundation

@MainActor
final class UsefulLinksStore: ObservableObject {
    @Published private(set) var items: [UsefulLink] = []

    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        load()
    }

    func add(title: String, urlOrText: String) {
        let body = urlOrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        var resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedTitle.isEmpty {
            resolvedTitle = String(body.prefix(80))
        }

        if let index = items.firstIndex(where: { $0.urlOrText == body }) {
            items[index].title = resolvedTitle
            items[index].lastUsedAt = Date()
            sortItems()
            save()
            return
        }

        items.append(UsefulLink(title: resolvedTitle, urlOrText: body))
        sortItems()
        save()
    }

    func update(_ link: UsefulLink, title: String, urlOrText: String) {
        let body = urlOrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        guard let index = items.firstIndex(where: { $0.id == link.id }) else { return }
        var resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedTitle.isEmpty {
            resolvedTitle = String(body.prefix(80))
        }
        items[index].title = resolvedTitle
        items[index].urlOrText = body
        items[index].lastUsedAt = Date()
        sortItems()
        save()
    }

    func delete(_ link: UsefulLink) {
        items.removeAll { $0.id == link.id }
        save()
    }

    func togglePin(_ link: UsefulLink) {
        guard let index = items.firstIndex(where: { $0.id == link.id }) else { return }
        items[index].isPinned.toggle()
        sortItems()
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func markUsed(_ link: UsefulLink) {
        guard let index = items.firstIndex(where: { $0.id == link.id }) else { return }
        items[index].lastUsedAt = Date()
        sortItems()
        save()
    }

    func filteredItems(matching query: String) -> [UsefulLink] {
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.urlOrText.localizedCaseInsensitiveContains(query)
        }
    }

    private func sortItems() {
        items.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.lastUsedAt > $1.lastUsedAt
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? decoder.decode([UsefulLink].self, from: data) else {
            return
        }
        items = decoded
        sortItems()
    }

    private func save() {
        do {
            let data = try encoder.encode(items)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            print("Failed to save useful links: \(error)")
        }
    }

    private static func defaultStorageURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = directory.appendingPathComponent("mac_tool", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory.appendingPathComponent("useful-links.json")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsefulLinksStoreTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/mac_tool/UsefulLink.swift Sources/mac_tool/UsefulLinksStore.swift Tests/mac_toolTests/UsefulLinksStoreTests.swift
git commit -m "$(cat <<'EOF'
feat: add UsefulLink model and UsefulLinksStore

EOF
)"
```

---

### Task 2: CardPresentation helpers

**Files:**
- Create: `Sources/mac_tool/CardPresentation.swift`
- Create: `Tests/mac_toolTests/CardPresentationTests.swift`

**Interfaces:**
- Produces:
  - `enum CardHeaderTone` with cases used by UI colors
  - `enum CardPresentation` static helpers:
    - `relativeTime(from: Date, now: Date = Date()) -> String`
    - `characterCountLabel(for: String) -> String`
    - `tone(forClipboardKind: ClipboardItem.Kind, value: String) -> CardHeaderTone`
    - `isShellLikeText(_ value: String) -> Bool`
    - `displayKindLabel(for: ClipboardItem.Kind) -> String`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import mac_tool

final class CardPresentationTests: XCTestCase {
    func testShellAllowlistUsesCommandTone() {
        XCTAssertTrue(CardPresentation.isShellLikeText("tl translate start"))
        XCTAssertTrue(CardPresentation.isShellLikeText("git status | cat"))
        XCTAssertFalse(CardPresentation.isShellLikeText("hello world"))
    }

    func testTextToneIsCommandWhenShellLike() {
        XCTAssertEqual(
            CardPresentation.tone(forClipboardKind: .text, value: "npm install"),
            .command
        )
        XCTAssertEqual(
            CardPresentation.tone(forClipboardKind: .text, value: "plain note"),
            .text
        )
    }

    func testKindTones() {
        XCTAssertEqual(CardPresentation.tone(forClipboardKind: .url, value: "https://a.com"), .url)
        XCTAssertEqual(CardPresentation.tone(forClipboardKind: .file, value: "a"), .file)
        XCTAssertEqual(CardPresentation.tone(forClipboardKind: .image, value: "a"), .image)
    }

    func testRelativeTimeYesterday() {
        let now = Date()
        let yesterday = now.addingTimeInterval(-25 * 60 * 60)
        XCTAssertEqual(CardPresentation.relativeTime(from: yesterday, now: now), "yesterday")
    }

    func testCharacterCountLabel() {
        XCTAssertEqual(CardPresentation.characterCountLabel(for: "hello"), "5 characters")
        XCTAssertEqual(CardPresentation.characterCountLabel(for: "a"), "1 character")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CardPresentationTests`

Expected: FAIL (type not found)

- [ ] **Step 3: Implement helpers**

```swift
import Foundation
import SwiftUI

enum CardHeaderTone {
    case text
    case command
    case url
    case file
    case image
    case link

    var color: Color {
        switch self {
        case .text: return Color(red: 0.20, green: 0.55, blue: 0.95)
        case .command: return Color(red: 0.90, green: 0.28, blue: 0.32)
        case .url: return Color(red: 0.15, green: 0.72, blue: 0.78)
        case .file: return Color(red: 0.22, green: 0.24, blue: 0.28)
        case .image: return Color(red: 0.55, green: 0.35, blue: 0.85)
        case .link: return Color(red: 0.12, green: 0.62, blue: 0.52)
        }
    }
}

enum CardPresentation {
    private static let shellAllowlist: Set<String> = [
        "tl", "git", "npm", "yarn", "pnpm", "flutter", "dart", "swift",
        "cd", "ls", "rm", "cp", "mv", "curl", "ssh"
    ]

    static func isShellLikeText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(" | ") { return true }
        let withoutSudo: String
        if trimmed.lowercased().hasPrefix("sudo ") {
            withoutSudo = String(trimmed.dropFirst(5))
        } else {
            withoutSudo = trimmed
        }
        let firstToken = withoutSudo.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        return shellAllowlist.contains(firstToken)
    }

    static func tone(forClipboardKind kind: ClipboardItem.Kind, value: String) -> CardHeaderTone {
        switch kind {
        case .url: return .url
        case .file: return .file
        case .image: return .image
        case .text, .other, .sensitive:
            return isShellLikeText(value) ? .command : .text
        }
    }

    static func displayKindLabel(for kind: ClipboardItem.Kind) -> String {
        switch kind {
        case .text, .other, .sensitive: return "Text"
        case .url: return "URL"
        case .file: return "File"
        case .image: return "Image"
        }
    }

    static func relativeTime(from date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }
        if seconds < 86_400 {
            let hours = Int(seconds / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        if seconds < 172_800 { return "yesterday" }
        let days = Int(seconds / 86_400)
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    static func characterCountLabel(for text: String) -> String {
        let count = text.count
        return count == 1 ? "1 character" : "\(count) characters"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CardPresentationTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/mac_tool/CardPresentation.swift Tests/mac_toolTests/CardPresentationTests.swift
git commit -m "$(cat <<'EOF'
feat: add card presentation helpers for tones and relative time

EOF
)"
```

---

### Task 3: Extend AppState for tabs, Useful Links, horizontal selection

**Files:**
- Modify: `Sources/mac_tool/AppState.swift`
- Modify: `Tests/mac_toolTests/AppStateTests.swift`

**Interfaces:**
- Consumes: `UsefulLinksStore`, `UsefulLink`, `ClipboardItem`
- Produces:
  - `enum PanelTab { case clipboard, usefulLinks }`
  - `@Published var selectedTab: PanelTab`
  - `@Published var isSearchExpanded: Bool`
  - `@Published var isLinkEditorPresented: Bool`
  - `@Published var linkEditorTitle: String`
  - `@Published var linkEditorBody: String`
  - `@Published var editingLinkID: UsefulLink.ID?`
  - `let usefulLinksStore: UsefulLinksStore`
  - `func moveSelection(left: Bool)` (replace `moveSelection(up:)`)
  - `func activateSelectedItem()`
  - `func activateClipboardItem(_ item: ClipboardItem)`
  - `func activateUsefulLink(_ link: UsefulLink)`
  - `func addClipboardItemToUsefulLinks(_ item: ClipboardItem)`
  - `func beginAddUsefulLink()`
  - `func beginEditUsefulLink(_ link: UsefulLink)`
  - `func saveLinkEditor()`
  - `func cancelLinkEditor()`
  - `func clearCurrentTab()`
  - `func collapseSearchIfNeeded()`
  - Keep `selectedItemID` as shared selection id across tabs (UUID)

- [ ] **Step 1: Update AppStateTests for horizontal API and useful-links wiring**

Replace `moveSelection(up:)` usages with `moveSelection(left:)` where `left: true` means toward start (previous index), `left: false` means toward end.

Add tests:

```swift
func testAddClipboardItemToUsefulLinks() {
    appState.clipboardStore.addText("https://example.com")
    let item = appState.clipboardStore.items[0]
    appState.addClipboardItemToUsefulLinks(item)
    XCTAssertEqual(appState.usefulLinksStore.items.count, 1)
    XCTAssertEqual(appState.usefulLinksStore.items[0].urlOrText, item.payload)
}

func testMoveSelectionLeftRightOnClipboard() {
    appState.selectedTab = .clipboard
    appState.clipboardStore.addText("A")
    appState.clipboardStore.addText("B")
    let items = appState.clipboardStore.filteredItems(matching: "")
    appState.selectedItemID = items.first?.id
    appState.moveSelection(left: false)
    XCTAssertEqual(appState.selectedItemID, items[1].id)
    appState.moveSelection(left: true)
    XCTAssertEqual(appState.selectedItemID, items[0].id)
}

func testClearCurrentTabClearsUsefulLinksOnly() {
    appState.clipboardStore.addText("keep")
    appState.usefulLinksStore.add(title: "x", urlOrText: "y")
    appState.selectedTab = .usefulLinks
    appState.clearCurrentTab()
    XCTAssertTrue(appState.usefulLinksStore.items.isEmpty)
    XCTAssertFalse(appState.clipboardStore.items.isEmpty)
}
```

Also update existing tests:
- `moveSelection(up: false)` → `moveSelection(left: false)`
- `moveSelection(up: true)` → `moveSelection(left: true)`

Wire `AppState` test instance to temp stores if needed. Prefer adding:

```swift
convenience init(clipboardStore: ClipboardStore, usefulLinksStore: UsefulLinksStore)
```

Or keep using default stores and `clearHistory` / `usefulLinksStore.clear()` in setUp — default Application Support is OK for local tests if cleared, but temp URLs are safer.

Update `AppState` init to accept optional storage URLs for both stores for tests:

```swift
init(
    clipboardStorageURL: URL? = nil,
    usefulLinksStorageURL: URL? = nil
) {
    self.clipboardStore = ClipboardStore(storageURL: clipboardStorageURL)
    self.usefulLinksStore = UsefulLinksStore(storageURL: usefulLinksStorageURL)
    // ...
}
```

Update `AppStateTests.setUp` to pass temp URLs.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppStateTests`

Expected: FAIL on new APIs / renamed method

- [ ] **Step 3: Implement AppState changes**

Key implementation sketch (merge into existing file; keep monitors and panelController):

```swift
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
    // ... monitors unchanged, but construct after stores ...

    init(clipboardStorageURL: URL? = nil, usefulLinksStorageURL: URL? = nil) {
        clipboardStore = ClipboardStore(storageURL: clipboardStorageURL)
        usefulLinksStore = UsefulLinksStore(storageURL: usefulLinksStorageURL)
        isAccessibilityTrusted = hotkeyMonitor.isAccessibilityTrusted
        startMonitoring()
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
        if let editingLinkID,
           let link = usefulLinksStore.items.first(where: { $0.id == editingLinkID }) {
            usefulLinksStore.update(link, title: linkEditorTitle, urlOrText: linkEditorBody)
        } else {
            usefulLinksStore.add(title: linkEditorTitle, urlOrText: linkEditorBody)
        }
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
        case .clipboard: clearHistory()
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

    func syncSelection() {
        let ids = activeItemIDs()
        if let selectedItemID, ids.contains(selectedItemID) { return }
        selectedItemID = ids.first
    }

    private func activeItemIDs() -> [UUID] {
        switch selectedTab {
        case .clipboard:
            return clipboardStore.filteredItems(matching: searchText).map(\.id)
        case .usefulLinks:
            return usefulLinksStore.filteredItems(matching: searchText).map(\.id)
        }
    }

    // Keep existing copyItemAndClose, clearHistory, accessibility, feedback helpers.
    // Remove old moveSelection(up:) and copySelectedItemAndClose — replace call sites with activateSelectedItem().
}
```

Ensure `ClipboardStore` remains creatable with `storageURL` (already is).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppStateTests`

Expected: PASS (also fix any compile breaks in `ClipboardPanelController` that still call `moveSelection(up:)` / `copySelectedItemAndClose` — temporarily alias or update in this task):

In this same task, update `ClipboardPanelController` call sites:

```swift
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
```

- [ ] **Step 5: Commit**

```bash
git add Sources/mac_tool/AppState.swift Sources/mac_tool/ClipboardPanelController.swift Tests/mac_toolTests/AppStateTests.swift
git commit -m "$(cat <<'EOF'
feat: add panel tabs and Useful Links actions to AppState

EOF
)"
```

---

### Task 4: Resize panel and polish Esc search collapse

**Files:**
- Modify: `Sources/mac_tool/ClipboardPanelController.swift`
- Modify: `Sources/mac_tool/AppState.swift` (Esc behavior via panel)

**Interfaces:**
- Consumes: `AppState.moveSelection(left:)`, `activateSelectedItem()`, `collapseSearchIfNeeded()`, `clearSearch()`, `isSearchExpanded`, `searchText`

- [ ] **Step 1: Update panel geometry**

In `ClipboardPanelController.init`, set content rect to `NSRect(x: 0, y: 0, width: 1100, height: 420)`.

- [ ] **Step 2: Update Esc handling**

```swift
case 53: // escape
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
```

- [ ] **Step 3: Build**

Run: `swift build`

Expected: success

- [ ] **Step 4: Commit**

```bash
git add Sources/mac_tool/ClipboardPanelController.swift Sources/mac_tool/AppState.swift
git commit -m "$(cat <<'EOF'
feat: widen clipboard panel and improve Esc search collapse

EOF
)"
```

---

### Task 5: Rewrite ContentView to horizontal card UI

**Files:**
- Modify: `Sources/mac_tool/ContentView.swift` (full rewrite)

**Interfaces:**
- Consumes: all `AppState` APIs from Task 3, `CardPresentation`, `UsefulLink`, `ClipboardItem`

- [ ] **Step 1: Replace ContentView with chrome + horizontal cards**

Rewrite `ContentView.swift` to include:

1. Outer glass `RoundedRectangle` cornerRadius 28, frame width 1100 height 420
2. Top bar `HStack` centered:
   - Search button toggles `isSearchExpanded`; when expanded show `TextField` bound to `searchText`
   - Clipboard pill button sets `selectedTab = .clipboard` then `syncSelection()`
   - Useful Links button sets tab; show red `Circle()` if `!usefulLinksStore.items.isEmpty`
   - `+` visible only when `selectedTab == .usefulLinks` → `beginAddUsefulLink()`
   - `Menu` with ⋯ : Clear current tab; if not accessibility trusted, request permission item
3. Body: if link editor presented, overlay form (Title, URL/Text, Save, Cancel)
4. Else horizontal `ScrollView(.horizontal)` of cards:
   - Clipboard: `ForEach(filteredClipboard)` → `HistoryCard`
   - Useful Links: `ForEach(filteredLinks)` → `LinkCard`
5. Card UI (~200×280): colored header (label + relative time + icon), white body (`lineLimit(8)`), footer char count + index
6. Selection: stroke when `item.id == selectedItemID`
7. Click → `activateClipboardItem` / `activateUsefulLink`
8. Context menus per spec
9. Empty states per tab
10. Keep feedback toast
11. `.onChange(of: selectedTab)` → `syncSelection()`
12. `.onChange(of: searchText)` → `syncSelection()`

Concrete card sketch:

```swift
struct HistoryCard: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool

    var body: some View {
        let tone = CardPresentation.tone(forClipboardKind: item.kind, value: item.value)
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(CardPresentation.displayKindLabel(for: item.kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(CardPresentation.relativeTime(from: item.lastUsedAt))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: item.kind == .file ? "doc.on.doc" : "bolt.fill")
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.color)

            Text(item.value)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
                .background(Color.white)

            HStack {
                Text(CardPresentation.characterCountLabel(for: item.payload))
                Spacer()
                Label("\(index)", systemImage: "list.bullet.rectangle")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white)
        }
        .frame(width: 200, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}
```

Mirror for `LinkCard` using `CardHeaderTone.link`, label `"Link"`, body showing `title` then `urlOrText`.

Top bar visual: dark pill for selected Clipboard (`Capsule` fill near-black, white text + `clock` icon). Useful Links: plain text + optional red dot.

- [ ] **Step 2: Build and run unit tests**

Run:

```bash
swift build
swift test
```

Expected: build success; all tests PASS

- [ ] **Step 3: Manual smoke (optional if GUI available)**

Run: `swift run`

Verify: `⌘⇧V` opens wide panel; horizontal cards; search expand; Useful Links add/open; clipboard context “Add to Useful Links”.

- [ ] **Step 4: Commit**

```bash
git add Sources/mac_tool/ContentView.swift
git commit -m "$(cat <<'EOF'
feat: redesign clipboard panel as horizontal glass card gallery

EOF
)"
```

---

### Task 6: README + final verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README feature list**

Add bullets for:
- Horizontal card gallery UI (`⌘⇧V`)
- Useful Links tab (manual add + favorite from clipboard)
- Expandable search on the current tab

Mention storage path for useful links JSON.

- [ ] **Step 2: Full test run**

Run: `swift test`

Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs: document horizontal panel UI and Useful Links

EOF
)"
```

---

## Spec Coverage Check

| Spec requirement | Task |
|------------------|------|
| Glass panel ~1100×420, radius ~28 | 4, 5 |
| Top bar search expand / Clipboard / Useful Links / + / ⋯ | 5 |
| Horizontal cards with colored header, body, footer | 2, 5 |
| Header tones including shell heuristic | 2, 5 |
| Clipboard store unchanged + context Add to Useful Links | 3, 5 |
| UsefulLink model + UsefulLinksStore persistence/dedupe/pin | 1 |
| AppState tabs, editor, activate open-or-copy | 3 |
| Left/right keyboard navigation | 3, 4 |
| Esc collapses search before close | 4 |
| Tests for store / presentation / AppState | 1, 2, 3 |
| README | 6 |
| Non-goals (no notarize/auto-paste/iCloud) | respected |

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-29-clipboard-panel-ui.md`.

Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks
2. **Inline Execution** — execute tasks in this session with executing-plans checkpoints

Which approach?
