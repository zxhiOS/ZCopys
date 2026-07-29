import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text
        case url
        case file
        case image
        case other      // 保留兼容旧数据
        case sensitive  // 保留兼容旧数据
    }

    let id: UUID
    let kind: Kind
    let value: String
    let payload: String
    let createdAt: Date
    var lastUsedAt: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        kind: Kind,
        value: String,
        payload: String? = nil,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.payload = payload ?? value
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt ?? createdAt
        self.isPinned = isPinned
    }
}
