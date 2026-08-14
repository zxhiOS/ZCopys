import XCTest
@testable import Zcopys

@MainActor
final class AppStateTests: XCTestCase {
    var appState: AppState!

    override func setUp() {
        super.setUp()
        let clipboardURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("appstate-clipboard-\(UUID().uuidString).json")
        let linksURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("appstate-links-\(UUID().uuidString).json")
        let categoriesURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("appstate-categories-\(UUID().uuidString).json")
        appState = AppState(
            clipboardStorageURL: clipboardURL,
            usefulLinksStorageURL: linksURL,
            categoriesStorageURL: categoriesURL,
            startMonitors: false,
            enableCloudKitSync: false
        )
    }

    override func tearDown() {
        appState = nil
        super.tearDown()
    }

    // MARK: - moveSelection

    func testMoveDownWithoutSelectionSelectsFirstItem() {
        appState.clipboardStore.addText("A")
        appState.clipboardStore.addText("B")
        appState.clipboardStore.addText("C")

        appState.selectedItemID = nil
        appState.moveSelection(left: false)

        let items = appState.clipboardStore.filteredItems(matching: "")
        XCTAssertEqual(appState.selectedItemID, items.first?.id)
    }

    func testMoveUpWithoutSelectionSelectsLastItem() {
        appState.clipboardStore.addText("A")
        appState.clipboardStore.addText("B")
        appState.clipboardStore.addText("C")

        appState.selectedItemID = nil
        appState.moveSelection(left: true)

        let items = appState.clipboardStore.filteredItems(matching: "")
        XCTAssertEqual(appState.selectedItemID, items.last?.id)
    }

    func testMoveSelectionOnEmptyListClearsSelection() {
        appState.clipboardStore.addText("X")
        appState.selectedItemID = appState.clipboardStore.filteredItems(matching: "").first?.id
        appState.clearHistory()

        appState.moveSelection(left: false)

        XCTAssertNil(appState.selectedItemID)
    }

    func testMoveUpAtTopStaysAtTop() {
        appState.clipboardStore.addText("A")
        appState.clipboardStore.addText("B")

        let items = appState.clipboardStore.filteredItems(matching: "")
        appState.selectedItemID = items.first?.id
        appState.moveSelection(left: true)

        XCTAssertEqual(appState.selectedItemID, items.first?.id)
    }

    func testMoveDownAtBottomStaysAtBottom() {
        appState.clipboardStore.addText("A")
        appState.clipboardStore.addText("B")

        let items = appState.clipboardStore.filteredItems(matching: "")
        appState.selectedItemID = items.last?.id
        appState.moveSelection(left: false)

        XCTAssertEqual(appState.selectedItemID, items.last?.id)
    }

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

    func testSaveLinkEditorKeepsEditorOpenOnEmptyBody() {
        appState.beginAddUsefulLink()
        appState.linkEditorTitle = "Title"
        appState.linkEditorBody = "   "
        appState.saveLinkEditor()
        XCTAssertTrue(appState.isLinkEditorPresented)
        XCTAssertTrue(appState.usefulLinksStore.items.isEmpty)
    }

    func testSaveLinkEditorDismissesAfterSuccessfulAdd() {
        appState.beginAddUsefulLink()
        appState.linkEditorTitle = "Docs"
        appState.linkEditorBody = "https://example.com"
        appState.saveLinkEditor()
        XCTAssertFalse(appState.isLinkEditorPresented)
        XCTAssertEqual(appState.usefulLinksStore.items.count, 1)
    }
}
