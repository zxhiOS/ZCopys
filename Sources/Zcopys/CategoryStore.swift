import Foundation

@MainActor
final class CategoryStore: ObservableObject {
    @Published private(set) var categories: [PanelCategory] = []

    /// Fired after local mutations so sync can upload.
    var onChange: (() -> Void)?

    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        load()
    }

    @discardableResult
    func add(name: String) -> PanelCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nextOrder = (categories.map(\.sortOrder).max() ?? -1) + 1
        let now = Date()
        let category = PanelCategory(name: trimmed, sortOrder: nextOrder, createdAt: now, updatedAt: now)
        categories.append(category)
        sortCategories()
        persistAndNotify()
        return category
    }

    @discardableResult
    func rename(_ category: PanelCategory, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return false }
        categories[index].name = trimmed
        categories[index].updatedAt = Date()
        persistAndNotify()
        return true
    }

    func delete(_ category: PanelCategory) {
        categories.removeAll { $0.id == category.id }
        normalizeSortOrders(touchUpdatedAt: true)
        persistAndNotify()
    }

    func move(_ category: PanelCategory, left: Bool) {
        sortCategories()
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        let target = left ? index - 1 : index + 1
        guard categories.indices.contains(target) else { return }
        categories.swapAt(index, target)
        normalizeSortOrders(touchUpdatedAt: true)
        persistAndNotify()
    }

    /// Replace local set after a cloud merge (does not notify sync to avoid loops).
    func replaceAll(_ newCategories: [PanelCategory], notify: Bool = false) {
        categories = newCategories
        sortCategories()
        save()
        if notify {
            onChange?()
        }
    }

    private func sortCategories() {
        categories.sort {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt < $1.createdAt
        }
    }

    private func normalizeSortOrders(touchUpdatedAt: Bool) {
        let now = Date()
        for index in categories.indices {
            categories[index].sortOrder = index
            if touchUpdatedAt {
                categories[index].updatedAt = now
            }
        }
    }

    private func persistAndNotify() {
        save()
        onChange?()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? decoder.decode([PanelCategory].self, from: data) else {
            return
        }
        categories = decoded
        sortCategories()
    }

    private func save() {
        do {
            let data = try encoder.encode(categories)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            print("Failed to save categories: \(error)")
        }
    }

    private static func defaultStorageURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = directory.appendingPathComponent("Zcopys", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory.appendingPathComponent("categories.json")
    }
}
