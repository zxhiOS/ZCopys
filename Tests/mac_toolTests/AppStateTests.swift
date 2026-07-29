import XCTest
@testable import mac_tool

@MainActor
final class AppStateTests: XCTestCase {
    var appState: AppState!

    override func setUp() {
        super.setUp()
        appState = AppState()
        appState.clearHistory()
    }

    override func tearDown() {
        appState.clearHistory()
        appState = nil
        super.tearDown()
    }

    // MARK: - moveSelection

    func testMoveDownWithoutSelectionSelectsFirstItem() {
        appState.clipboardStore.addText("A")
        appState.clipboardStore.addText("B")
        appState.clipboardStore.addText("C")

        appState.selectedItemID = nil
        appState.moveSelection(up: false)

        let items = appState.clipboardStore.filteredItems(matching: "")
        XCTAssertEqual(appState.selectedItemID, items.first?.id)
    }

    func testMoveUpWithoutSelectionSelectsLastItem() {
        appState.clipboardStore.addText("A")
        appState.clipboardStore.addText("B")
        appState.clipboardStore.addText("C")

        appState.selectedItemID = nil
        appState.moveSelection(up: true)

        let items = appState.clipboardStore.filteredItems(matching: "")
        XCTAssertEqual(appState.selectedItemID, items.last?.id)
    }

    func testMoveSelectionOnEmptyListClearsSelection() {
        appState.clipboardStore.addText("X")
        appState.selectedItemID = appState.clipboardStore.filteredItems(matching: "").first?.id
        appState.clearHistory()

        appState.moveSelection(up: false)

        XCTAssertNil(appState.selectedItemID)
    }

    func testMoveUpAtTopStaysAtTop() {
        appState.clipboardStore.addText("A")
        appState.clipboardStore.addText("B")

        let items = appState.clipboardStore.filteredItems(matching: "")
        appState.selectedItemID = items.first?.id
        appState.moveSelection(up: true)

        XCTAssertEqual(appState.selectedItemID, items.first?.id)
    }

    func testMoveDownAtBottomStaysAtBottom() {
        appState.clipboardStore.addText("A")
        appState.clipboardStore.addText("B")

        let items = appState.clipboardStore.filteredItems(matching: "")
        appState.selectedItemID = items.last?.id
        appState.moveSelection(up: false)

        XCTAssertEqual(appState.selectedItemID, items.last?.id)
    }
}
