import XCTest
@testable import Zcopys

final class SyncMergeTests: XCTestCase {
    func testCategoryMergePrefersNewerUpdatedAt() {
        let id = UUID()
        let older = PanelCategory(id: id, name: "Old", sortOrder: 0, createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2))
        let newer = PanelCategory(id: id, name: "New", sortOrder: 1, createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 10))
        let merged = SyncMerge.categories(local: [older], remote: [newer])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "New")
        XCTAssertEqual(merged[0].sortOrder, 1)
    }

    func testLinkMergeUnionsDistinctIDs() {
        let a = UsefulLink(title: "A", urlOrText: "a", categoryId: nil)
        let b = UsefulLink(title: "B", urlOrText: "b", categoryId: nil)
        let merged = SyncMerge.links(local: [a], remote: [b])
        XCTAssertEqual(Set(merged.map(\.title)), Set(["A", "B"]))
    }
}
