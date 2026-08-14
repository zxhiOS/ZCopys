import XCTest
@testable import Zcopys

@MainActor
final class CategoryStoreTests: XCTestCase {
    func testAddRenameMoveDelete() {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zcopys-categories-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storageURL) }

        let store = CategoryStore(storageURL: storageURL)
        let first = store.add(name: " Work ")!
        let second = store.add(name: "Personal")!
        XCTAssertEqual(store.categories.map(\.name), ["Work", "Personal"])

        XCTAssertTrue(store.rename(first, to: "Office"))
        XCTAssertEqual(store.categories.first { $0.id == first.id }?.name, "Office")

        store.move(second, left: true)
        XCTAssertEqual(store.categories.map(\.name), ["Personal", "Office"])

        store.delete(first)
        XCTAssertEqual(store.categories.map(\.name), ["Personal"])
    }

    func testAddRejectsEmptyName() {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zcopys-categories-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storageURL) }
        let store = CategoryStore(storageURL: storageURL)
        XCTAssertNil(store.add(name: "   "))
        XCTAssertTrue(store.categories.isEmpty)
    }
}
