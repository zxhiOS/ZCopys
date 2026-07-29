import Foundation
import SwiftUI

enum CardHeaderTone {
    case text
    case command
    case url
    case file
    case image
    case link

    var color: Color {
        switch self {
        case .text: return Color(red: 0.20, green: 0.55, blue: 0.95)
        case .command: return Color(red: 0.90, green: 0.28, blue: 0.32)
        case .url: return Color(red: 0.15, green: 0.72, blue: 0.78)
        case .file: return Color(red: 0.22, green: 0.24, blue: 0.28)
        case .image: return Color(red: 0.55, green: 0.35, blue: 0.85)
        case .link: return Color(red: 0.12, green: 0.62, blue: 0.52)
        }
    }
}

enum CardPresentation {
    private static let shellAllowlist: Set<String> = [
        "tl", "git", "npm", "yarn", "pnpm", "flutter", "dart", "swift",
        "cd", "ls", "rm", "cp", "mv", "curl", "ssh"
    ]

    static func isShellLikeText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(" | ") { return true }
        let withoutSudo: String
        if trimmed.lowercased().hasPrefix("sudo ") {
            withoutSudo = String(trimmed.dropFirst(5))
        } else {
            withoutSudo = trimmed
        }
        let firstToken = withoutSudo.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        return shellAllowlist.contains(firstToken)
    }

    static func tone(forClipboardKind kind: ClipboardItem.Kind, value: String) -> CardHeaderTone {
        switch kind {
        case .url: return .url
        case .file: return .file
        case .image: return .image
        case .text, .other, .sensitive:
            return isShellLikeText(value) ? .command : .text
        }
    }

    static func displayKindLabel(for kind: ClipboardItem.Kind) -> String {
        switch kind {
        case .text, .other, .sensitive: return "Text"
        case .url: return "URL"
        case .file: return "File"
        case .image: return "Image"
        }
    }

    static func relativeTime(from date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }
        if seconds < 86_400 {
            let hours = Int(seconds / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        if seconds < 172_800 { return "yesterday" }
        let days = Int(seconds / 86_400)
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    static func characterCountLabel(for text: String) -> String {
        let count = text.count
        return count == 1 ? "1 character" : "\(count) characters"
    }
}
