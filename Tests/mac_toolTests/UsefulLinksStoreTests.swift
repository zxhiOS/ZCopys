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
