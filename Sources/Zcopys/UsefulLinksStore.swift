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

    @discardableResult
    func add(title: String, urlOrText: String) -> Bool {
        let body = urlOrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        var resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedTitle.isEmpty {
            resolvedTitle = String(body.prefix(80))
        }

        if let index = items.firstIndex(where: { $0.urlOrText == body }) {
            items[index].title = resolvedTitle
            items[index].lastUsedAt = Date()
            sortItems()
            save()
            return true
        }

        items.append(UsefulLink(title: resolvedTitle, urlOrText: body))
        sortItems()
        save()
        return true
    }

    @discardableResult
    func update(_ link: UsefulLink, title: String, urlOrText: String) -> Bool {
        let body = urlOrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        guard let index = items.firstIndex(where: { $0.id == link.id }) else { return false }
        var resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedTitle.isEmpty {
            resolvedTitle = String(body.prefix(80))
        }

        if let duplicateIndex = items.firstIndex(where: { $0.id != link.id && $0.urlOrText == body }) {
            items[duplicateIndex].title = resolvedTitle
            items[duplicateIndex].lastUsedAt = Date()
            items.remove(at: index)
            sortItems()
            save()
            return true
        }

        items[index].title = resolvedTitle
        items[index].urlOrText = body
        items[index].lastUsedAt = Date()
        sortItems()
        save()
        return true
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
        let appDirectory = directory.appendingPathComponent("Zcopys", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        let url = appDirectory.appendingPathComponent("useful-links.json")
        let legacy = directory
            .appendingPathComponent("mac_tool", isDirectory: true)
            .appendingPathComponent("useful-links.json")
        if !FileManager.default.fileExists(atPath: url.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.copyItem(at: legacy, to: url)
        }
        return url
    }
}
