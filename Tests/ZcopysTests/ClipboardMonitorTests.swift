import XCTest
import AppKit
@testable import Zcopys

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    func testPollDeliversNewTextSynchronously() {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("seed", forType: .string)

        var received: String?
        let monitor = ClipboardMonitor(
            onTextCopy: { received = $0 },
            onFileCopy: { _ in },
            onImageCopy: { _ in }
        )

        pasteboard.clearContents()
        pasteboard.setString("first copy after open", forType: .string)
        XCTAssertNotEqual(pasteboard.changeCount, previousChangeCount)

        monitor.poll()

        XCTAssertEqual(
            received,
            "first copy after open",
            "poll must deliver on the current run loop turn so the panel can show the latest copy"
        )
    }
}
