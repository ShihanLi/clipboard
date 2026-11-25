import AppKit
import CryptoKit

/// One entry in the clipboard history.
struct ClipItem {
    enum Kind { case text, image }

    var kind: Kind
    var text: String?
    var rtf: Data?
    var png: Data?
    var image: NSImage?
    var hash: String
}

/// Keeps the most recent clipboard items in memory only.
/// Nothing is written to disk; history is gone when the app quits.
final class HistoryStore {
    static let maxItems = 50

    private(set) var items: [ClipItem] = []

    func addText(_ text: String, rtf: Data?) {
        let hash = Self.sha(Data(("t:" + text).utf8))
        if moveToTop(hash: hash) { return }
        insert(ClipItem(kind: .text, text: text, rtf: rtf, hash: hash))
    }

    func addImage(png: Data) {
        let hash = Self.sha(png)
        if moveToTop(hash: hash) { return }
        insert(ClipItem(kind: .image, png: png, image: NSImage(data: png), hash: hash))
    }

    /// Moves an existing item to the top of the list.
    func promote(_ item: ClipItem) {
        _ = moveToTop(hash: item.hash)
    }

    func clear() {
        items.removeAll()
    }

    private func moveToTop(hash: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.hash == hash }) else { return false }
        items.insert(items.remove(at: index), at: 0)
        return true
    }

    private func insert(_ item: ClipItem) {
        items.insert(item, at: 0)
        if items.count > Self.maxItems { items.removeLast(items.count - Self.maxItems) }
    }

    private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
