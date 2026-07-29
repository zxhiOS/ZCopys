import XCTest
@testable import Zcopys

@MainActor
final class ClipboardStoreTests: XCTestCase {
    func testPinnedItemsRemainAheadOfRecentItems() {
        withStore { store in
            store.addText("pinned")
            store.togglePin(store.items[0])
            store.addText("recent")

            XCTAssertEqual(store.items.map(\.value), ["pinned", "recent"])
        }
    }

    func testRepeatedContentUpdatesTheExistingItem() {
        withStore { store in
            store.addText("first")
            store.addText("second")
            store.addText("first")

            XCTAssertEqual(store.items.map(\.value), ["first", "second"])
        }
    }

    func testSensitiveValuesAreNotRecorded() {
        withStore { store in
            store.addText("4242-4242-4242-4242")
            store.addText("sk-123456789012345678901234567890")
            store.addText("safe text")

            XCTAssertEqual(store.items.map(\.value), ["safe text"])
        }
    }

    func testUnpinnedHistoryIsCappedAtTwoHundredItems() {
        withStore { store in
            for index in 0...200 {
                store.addText("entry \(index)")
            }

            XCTAssertEqual(store.items.count, 200)
            XCTAssertEqual(store.items.first?.value, "entry 200")
            XCTAssertEqual(store.items.last?.value, "entry 1")
        }
    }
    func testTogglePinSetsIsPinnedToTrue() {
        withStore { store in
            store.addText("item")
            let item = store.items[0]
            XCTAssertFalse(item.isPinned)

            store.togglePin(item)
            XCTAssertTrue(store.items.first(where: { $0.id == item.id })?.isPinned ?? false)
        }
    }

    func testTogglePinTwiceReturnsToUnpinned() {
        withStore { store in
            store.addText("item")
            let item = store.items[0]

            store.togglePin(item)
            store.togglePin(store.items.first(where: { $0.id == item.id })!)
            XCTAssertFalse(store.items.first(where: { $0.id == item.id })?.isPinned ?? true)
        }
    }

    func testPinnedItemStaysAheadWhenAddingNewItems() {
        withStore { store in
            store.addText("A")
            store.addText("B")
            store.togglePin(store.items.first(where: { $0.value == "B" })!)
            store.addText("C")

            let values = store.items.map(\.value)
            XCTAssertEqual(values.first, "B")
            XCTAssertTrue(values.contains("A"))
            XCTAssertTrue(values.contains("C"))
        }
    }


    private func withStore(_ body: (ClipboardStore) -> Void) {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zcopys-tests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storageURL) }
        body(ClipboardStore(storageURL: storageURL))
    }
}
