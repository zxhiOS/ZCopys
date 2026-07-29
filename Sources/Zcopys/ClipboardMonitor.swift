import AppKit
import Foundation

final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let onTextCopy: @MainActor (String) -> Void
    private let onFileCopy: @MainActor ([URL]) -> Void
    private let onImageCopy: @MainActor (NSImage) -> Void

    init(
        onTextCopy: @escaping @MainActor (String) -> Void,
        onFileCopy: @escaping @MainActor ([URL]) -> Void = { _ in },
        onImageCopy: @escaping @MainActor (NSImage) -> Void = { _ in }
    ) {
        self.onTextCopy = onTextCopy
        self.onFileCopy = onFileCopy
        self.onImageCopy = onImageCopy
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let fileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileURLReadingOptions) as? [URL], !urls.isEmpty {
            Task { @MainActor in
                onFileCopy(urls)
            }
            return
        }

        if let image = NSImage(pasteboard: pasteboard) {
            Task { @MainActor in
                onImageCopy(image)
            }
            return
        }

        if let text = pasteboard.string(forType: .string) {
            Task { @MainActor in
                onTextCopy(text)
            }
        }
    }
}
