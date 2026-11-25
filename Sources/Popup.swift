import AppKit

/// A floating panel that never takes focus, so the app you're pasting into stays active.
private final class PopupPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class RowView: NSView {
    var onClick: () -> Void = {}
    var onHover: () -> Void = {}
    var isSelected = false { didSet { updateColors() } }

    private let indexLabel = NSTextField(labelWithString: "")
    private let textLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?

    init(index: Int, item: ClipItem, image: NSImage?, width: CGFloat, height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        wantsLayer = true
        layer?.cornerRadius = 6

        indexLabel.stringValue = index < 9 ? "\(index + 1)" : ""
        indexLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        indexLabel.alignment = .center
        indexLabel.frame = NSRect(x: 6, y: (height - 16) / 2, width: 16, height: 16)
        addSubview(indexLabel)

        let contentX: CGFloat = 28
        let contentWidth = width - contentX - 10
        if item.kind == .image, let image {
            let imageView = NSImageView(frame: NSRect(x: contentX, y: 5, width: contentWidth, height: height - 10))
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyDown
            imageView.imageAlignment = .alignLeft
            addSubview(imageView)
            textLabel.stringValue = "\(Int(image.size.width))×\(Int(image.size.height))"
            textLabel.font = .systemFont(ofSize: 10)
            textLabel.alignment = .right
            textLabel.frame = NSRect(x: contentX, y: 4, width: contentWidth, height: 14)
            addSubview(textLabel)
        } else {
            let raw = item.text ?? ""
            let collapsed = raw.prefix(300)
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            textLabel.stringValue = collapsed
            textLabel.font = .systemFont(ofSize: 13)
            textLabel.lineBreakMode = .byTruncatingTail
            textLabel.cell?.truncatesLastVisibleLine = true
            textLabel.frame = NSRect(x: contentX, y: (height - 18) / 2, width: contentWidth, height: 18)
            addSubview(textLabel)
        }
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func mouseEntered(with event: NSEvent) { onHover() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    private func updateColors() {
        layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        textLabel.textColor = isSelected ? .white : .labelColor
        indexLabel.textColor = isSelected ? NSColor.white.withAlphaComponent(0.8) : .tertiaryLabelColor
    }
}

/// Shows the clipboard history next to the mouse pointer.
final class PopupController {
    var onChoose: (ClipItem) -> Void = { _ in }

    private let store: HistoryStore
    private let panel = PopupPanel()
    private var rows: [RowView] = []
    private var items: [ClipItem] = []
    private var selected = 0
    private var scrollView: NSScrollView?
    private var clickMonitor: Any?

    private let width: CGFloat = 360
    private let padding: CGFloat = 6
    private let maxHeight: CGFloat = 460

    init(store: HistoryStore) { self.store = store }

    var isVisible: Bool { panel.isVisible }

    func show() {
        items = store.items
        selected = 0
        buildContent()
        position()
        panel.orderFrontRegardless()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    /// Handles a key press while the popup is open. Returns true if the key was used.
    func handleKey(_ keyCode: Int64) -> Bool {
        let digitKeys: [Int64: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
        switch keyCode {
        case 53: // Esc
            close()
        case 125: // Down
            select(min(selected + 1, items.count - 1))
        case 126: // Up
            select(max(selected - 1, 0))
        case 36, 76: // Return, Enter
            choose(selected)
        default:
            if let index = digitKeys[keyCode] {
                choose(index)
            } else {
                // Any other key closes the popup and goes through to the app.
                close()
                return false
            }
        }
        return true
    }

    // MARK: Private

    private func choose(_ index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        close()
        onChoose(item)
    }

    private func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        rows[selected].isSelected = false
        selected = index
        rows[index].isSelected = true
        rows[index].scrollToVisible(rows[index].bounds)
    }

    private func buildContent() {
        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true

        rows = []
        let rowWidth = width - padding * 2
        let document = FlippedView()
        var y: CGFloat = padding

        if items.isEmpty {
            let label = NSTextField(labelWithString: "No clipboard history yet")
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.frame = NSRect(x: padding, y: 14, width: rowWidth, height: 18)
            document.addSubview(label)
            y = 46
        } else {
            for (index, item) in items.enumerated() {
                let height: CGFloat = item.kind == .image ? 64 : 30
                let row = RowView(index: index, item: item, image: item.image, width: rowWidth, height: height)
                row.frame.origin = NSPoint(x: padding, y: y)
                row.onClick = { [weak self] in self?.choose(index) }
                row.onHover = { [weak self] in self?.select(index) }
                row.isSelected = index == selected
                document.addSubview(row)
                rows.append(row)
                y += height + 2
            }
            y += padding - 2
        }

        let contentHeight = y
        let visibleHeight = min(contentHeight, maxHeight)
        document.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: visibleHeight))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = contentHeight > maxHeight
        scroll.scrollerStyle = .overlay
        scroll.documentView = document
        scroll.contentView.scroll(to: .zero)
        scrollView = scroll

        background.frame = scroll.frame
        background.addSubview(scroll)
        panel.contentView = background
        panel.setContentSize(scroll.frame.size)
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? .zero
        let size = panel.frame.size

        var x = mouse.x + 4
        var y = mouse.y - size.height - 4          // open below the pointer
        if x + size.width > bounds.maxX { x = mouse.x - size.width - 4 }
        if y < bounds.minY { y = mouse.y + 4 }      // no room below: open above
        x = max(bounds.minX, min(x, bounds.maxX - size.width))
        y = max(bounds.minY, min(y, bounds.maxY - size.height))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
