import AppKit

/// One entry in the clipboard history.
enum ClipItem {
    case text(String, rtf: Data?)
    case image(png: Data, NSImage)

    /// Two items are the same copy if their text or image bytes match.
    func isSame(as other: ClipItem) -> Bool {
        switch (self, other) {
        case let (.text(a, _), .text(b, _)): return a == b
        case let (.image(a, _), .image(b, _)): return a == b
        default: return false
        }
    }
}

/// Keeps the most recent clipboard items in memory only.
/// Nothing is written to disk; history is gone when the app quits.
final class HistoryStore {
    static let maxItems = 50

    private(set) var items: [ClipItem] = []

    /// Puts an item at the top, moving it there if it's already in the history.
    func add(_ item: ClipItem) {
        items.removeAll { $0.isSame(as: item) }
        items.insert(item, at: 0)
        if items.count > Self.maxItems { items.removeLast(items.count - Self.maxItems) }
    }

    func clear() {
        items.removeAll()
    }
}
