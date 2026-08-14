import AppKit
import UniformTypeIdentifiers

enum DragExport {
    /// Build a provider other apps' text fields / image views can accept.
    static func itemProvider(for item: ClipboardItem) -> NSItemProvider {
        switch item.kind {
        case .file:
            let urls = item.payload
                .split(separator: "\n")
                .map(String.init)
                .map { URL(fileURLWithPath: $0) }
            if let first = urls.first, FileManager.default.fileExists(atPath: first.path),
               let provider = NSItemProvider(contentsOf: first) {
                return provider
            }
            return plainTextProvider(item.value)

        case .image:
            if let data = Data(base64Encoded: item.payload), let image = NSImage(data: data) {
                return NSItemProvider(object: image)
            }
            return plainTextProvider(item.value)

        default:
            return plainTextProvider(item.payload)
        }
    }

    static func itemProvider(for link: UsefulLink) -> NSItemProvider {
        if let url = URL(string: link.urlOrText),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            let provider = NSItemProvider(object: url as NSURL)
            // Also offer plain text so generic text fields accept the drop.
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.utf8PlainText.identifier,
                visibility: .all
            ) { completion in
                completion(link.urlOrText.data(using: .utf8), nil)
                return nil
            }
            return provider
        }
        return plainTextProvider(link.urlOrText)
    }

    private static func plainTextProvider(_ text: String) -> NSItemProvider {
        let provider = NSItemProvider(object: text as NSString)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier,
            visibility: .all
        ) { completion in
            completion(text.data(using: .utf8), nil)
            return nil
        }
        return provider
    }
}
