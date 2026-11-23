import AppKit
import CryptoKit

/// One entry in the clipboard history.
struct ClipItem: Codable, Identifiable {
    enum Kind: String, Codable { case text, image }

    var id = UUID()
    var kind: Kind
    var text: String?
    var rtf: Data?
    var imageFile: String?
    var hash: String
    var date = Date()
}

/// Stores the most recent clipboard items on disk in
/// ~/Library/Application Support/Clipboard.
final class HistoryStore {
    static let maxItems = 50

    private(set) var items: [ClipItem] = []
    private let dir: URL
    private let imagesDir: URL
    private let indexFile: URL
    private var imageCache: [UUID: NSImage] = [:]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = support.appendingPathComponent("Clipboard", isDirectory: true)
        imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        indexFile = dir.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Adding

    func addText(_ text: String, rtf: Data?) {
        let hash = Self.sha("t:" + text)
        if moveToTop(hash: hash) { return }
        insert(ClipItem(kind: .text, text: text, rtf: rtf, hash: hash))
    }

    func addImage(png: Data) {
        let hash = Self.sha(png)
        if moveToTop(hash: hash) { return }
        var item = ClipItem(kind: .image, hash: hash)
        let name = item.id.uuidString + ".png"
        do {
            try png.write(to: imagesDir.appendingPathComponent(name), options: .atomic)
        } catch { return }
        item.imageFile = name
        insert(item)
    }

    /// Moves an existing item to the top of the list.
    func promote(_ item: ClipItem) {
        _ = moveToTop(hash: item.hash)
    }

    func clear() {
        items.removeAll()
        imageCache.removeAll()
        try? FileManager.default.removeItem(at: imagesDir)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        save()
    }

    // MARK: Reading

    func image(for item: ClipItem) -> NSImage? {
        if let cached = imageCache[item.id] { return cached }
        guard let name = item.imageFile,
              let image = NSImage(contentsOf: imagesDir.appendingPathComponent(name)) else { return nil }
        imageCache[item.id] = image
        return image
    }

    func imageData(for item: ClipItem) -> Data? {
        guard let name = item.imageFile else { return nil }
        return try? Data(contentsOf: imagesDir.appendingPathComponent(name))
    }

    // MARK: Private

    private func moveToTop(hash: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.hash == hash }) else { return false }
        var item = items.remove(at: index)
        item.date = Date()
        items.insert(item, at: 0)
        save()
        return true
    }

    private func insert(_ item: ClipItem) {
        items.insert(item, at: 0)
        while items.count > Self.maxItems {
            let removed = items.removeLast()
            imageCache[removed.id] = nil
            if let name = removed.imageFile {
                try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(name))
            }
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexFile),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        items = decoded.filter { item in
            guard item.kind == .image else { return true }
            guard let name = item.imageFile else { return false }
            return FileManager.default.fileExists(atPath: imagesDir.appendingPathComponent(name).path)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexFile, options: .atomic)
    }

    private static func sha(_ string: String) -> String { sha(Data(string.utf8)) }
    private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
