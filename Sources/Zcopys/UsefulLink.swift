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
