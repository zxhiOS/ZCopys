import XCTest
@testable import Zcopys

final class CardPresentationTests: XCTestCase {
    func testShellAllowlistUsesCommandTone() {
        XCTAssertTrue(CardPresentation.isShellLikeText("tl translate start"))
        XCTAssertTrue(CardPresentation.isShellLikeText("git status | cat"))
        XCTAssertFalse(CardPresentation.isShellLikeText("hello world"))
    }

    func testTextToneIsCommandWhenShellLike() {
        XCTAssertEqual(
            CardPresentation.tone(forClipboardKind: .text, value: "npm install"),
            .command
        )
        XCTAssertEqual(
            CardPresentation.tone(forClipboardKind: .text, value: "plain note"),
            .text
        )
    }

    func testKindTones() {
        XCTAssertEqual(CardPresentation.tone(forClipboardKind: .url, value: "https://a.com"), .url)
        XCTAssertEqual(CardPresentation.tone(forClipboardKind: .file, value: "a"), .file)
        XCTAssertEqual(CardPresentation.tone(forClipboardKind: .image, value: "a"), .image)
    }

    func testRelativeTimeYesterday() {
        let now = Date()
        let yesterday = now.addingTimeInterval(-25 * 60 * 60)
        XCTAssertEqual(CardPresentation.relativeTime(from: yesterday, now: now), "yesterday")
    }

    func testCharacterCountLabel() {
        XCTAssertEqual(CardPresentation.characterCountLabel(for: "hello"), "5 characters")
        XCTAssertEqual(CardPresentation.characterCountLabel(for: "a"), "1 character")
    }
}
