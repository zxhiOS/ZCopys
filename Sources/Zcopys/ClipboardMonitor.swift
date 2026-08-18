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
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Reads the pasteboard on the current run loop turn. Must be synchronous:
    /// `Task { @MainActor in }` would hop a frame, so ⌘⇧V right after ⌘C showed
    /// a stale panel until the next open.
    func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let fileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileURLReadingOptions) as? [URL], !urls.isEmpty {
            invokeOnMain { self.onFileCopy(urls) }
            return
        }

        if let image = NSImage(pasteboard: pasteboard), pasteboard.string(forType: .string) == nil {
            invokeOnMain { self.onImageCopy(image) }
            return
        }

        if let text = pasteboard.string(forType: .string) {
            invokeOnMain { self.onTextCopy(text) }
        } else if let image = NSImage(pasteboard: pasteboard) {
            invokeOnMain { self.onImageCopy(image) }
        }
    }

    private func invokeOnMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated(body)
            }
        }
    }
}
