import Foundation

struct UsefulLink: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var urlOrText: String
    let createdAt: Date
    var lastUsedAt: Date
    var updatedAt: Date
    var isPinned: Bool
    /// `nil` = Useful Links tab; otherwise a custom category id.
    var categoryId: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        urlOrText: String,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        updatedAt: Date? = nil,
        isPinned: Bool = false,
        categoryId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.urlOrText = urlOrText
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt ?? createdAt
        self.updatedAt = updatedAt ?? self.lastUsedAt
        self.isPinned = isPinned
        self.categoryId = categoryId
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, urlOrText, createdAt, lastUsedAt, updatedAt, isPinned, categoryId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        urlOrText = try container.decode(String.self, forKey: .urlOrText)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decode(Date.self, forKey: .lastUsedAt)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? lastUsedAt
    }
}
