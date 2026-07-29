import Foundation
import AppKit

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maximumUnpinnedItems = 200
    private let maximumUnpinnedImages = 30
    private let maximumImageBytes = 8 * 1024 * 1024
    private let maximumImageHistoryBytes = 80 * 1024 * 1024

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        load()
    }

    func addText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !Self.isSensitive(trimmed) else { return }

        let kind: ClipboardItem.Kind = trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://")
            ? .url
            : .text

        record(ClipboardItem(kind: kind, value: trimmed))
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        sortItems()
        trimItems()
        save()
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    @discardableResult
    func copyToClipboard(_ item: ClipboardItem) -> Bool {
        // macOS 14+ 要求在前台才能写入剪贴板
        NSApplication.shared.activate(ignoringOtherApps: true)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let didWrite: Bool
        switch item.kind {
        case .file:
            let urls = item.payload.split(separator: "\n").map(String.init).compactMap(URL.init(fileURLWithPath:))
            guard !urls.isEmpty else { return false }
            didWrite = pasteboard.writeObjects(urls as [NSURL])
        case .image:
            if let data = Data(base64Encoded: item.payload), let image = NSImage(data: data) {
                didWrite = pasteboard.writeObjects([image])
            } else {
                didWrite = pasteboard.setString(item.value, forType: .string)
            }
        default:
            didWrite = pasteboard.setString(item.payload, forType: .string)
        }

        guard didWrite else { return false }
        markUsed(item)
        return true
    }

    func addFileURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let paths = urls.map(\.path)
        let label = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        let item = ClipboardItem(kind: .file, value: label, payload: paths.joined(separator: "\n"))
        record(item)
    }

    func addImage(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation else { return }
        guard tiff.count <= maximumImageBytes else { return }
        let payload = tiff.base64EncodedString()
        let size = image.size
        let label = "Image \(Int(size.width))×\(Int(size.height))"
        let item = ClipboardItem(kind: .image, value: label, payload: payload)
        record(item)
    }

    func clear() {
        items.removeAll()
        save()
    }

    func filteredItems(matching query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.value.localizedCaseInsensitiveContains(query)
        }
    }

    private func sortItems() {
        items.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.lastUsedAt > $1.lastUsedAt
        }
    }

    private func markUsed(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].lastUsedAt = Date()
        sortItems()
        save()
    }

    private func record(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.kind == item.kind && $0.payload == item.payload }) {
            items[index].lastUsedAt = Date()
            sortItems()
            save()
            return
        }

        items.append(item)
        sortItems()
        trimItems()
        save()
    }

    private func trimItems() {
        var retainedItems = items.filter(\.isPinned)
        var retainedUnpinnedItems = 0
        var retainedImages = 0
        var retainedImageBytes = 0

        for item in items where !item.isPinned {
            guard retainedUnpinnedItems < maximumUnpinnedItems else { break }

            if item.kind == .image {
                let imageBytes = item.payload.utf8.count
                guard retainedImages < maximumUnpinnedImages,
                      retainedImageBytes + imageBytes <= maximumImageHistoryBytes else {
                    continue
                }
                retainedImages += 1
                retainedImageBytes += imageBytes
            }

            retainedItems.append(item)
            retainedUnpinnedItems += 1
        }

        items = retainedItems
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? decoder.decode([ClipboardItem].self, from: data) else {
            return
        }
        items = decoded
        sortItems()
        trimItems()
    }

    private func save() {
        do {
            let data = try encoder.encode(items)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            print("Failed to save clipboard history: \(error)")
        }
    }

    private static func defaultStorageURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = directory.appendingPathComponent("Zcopys", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        let url = appDirectory.appendingPathComponent("clipboard-history.json")
        // Migrate from legacy mac_tool storage if needed
        let legacy = directory
            .appendingPathComponent("mac_tool", isDirectory: true)
            .appendingPathComponent("clipboard-history.json")
        if !FileManager.default.fileExists(atPath: url.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.copyItem(at: legacy, to: url)
        }
        return url
    }

    private static func isSensitive(_ value: String) -> Bool {
        // 先检查依赖连字符的模式（原值，不归一化）
        if let _ = value.range(of: #"\bsk-[A-Za-z0-9_-]{20,}\b"#, options: .regularExpression) {
            return true
        }

        let normalized = value.replacingOccurrences(of: #"[\s-]"#, with: "", options: .regularExpression)

        let patterns = [
            #"^\d{6}$"#,                           // 验证码
            #"^\d{12,19}$"#,                       // 常见卡号
            #"(?i)password\s*[:=]"#,               // 密码标记
            #"(?i)verification\s*code\s*[:=]"#,   // 验证码标记
            #"(?i)otp\s*[:=]"#,                   // 一次性验证码
            #"(?i)secret\s*[:=]"#,                // 密钥标记
            #"\bsk-[A-Za-z0-9_-]{20,}\b"#,
            #"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"#,
            #"\bgithub_pat_[A-Za-z0-9_]{20,}\b"#,
            #"\bAKIA[0-9A-Z]{16}\b"#,
            #"(?i)bearer\s+[A-Za-z0-9._~-]{16,}"#,
            #"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"#
        ]

        for pattern in patterns {
            if normalized.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        return normalized.contains("-----BEGIN") && normalized.contains("PRIVATE KEY-----")
    }
}
