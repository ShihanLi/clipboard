import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = HistoryStore()
    private lazy var monitor = PasteboardMonitor(store: store)
    private lazy var popup = PopupController(store: store)
    private let keyTap = KeyTap()
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMenuBar()
        setUpLaunchAtLoginOnFirstRun()
        monitor.start()

        popup.onChoose = { [weak self] item in self?.paste(item) }
        keyTap.onHold = { [weak self] in self?.popup.show() }
        keyTap.isPopupVisible = { [weak self] in self?.popup.isVisible ?? false }
        keyTap.popupKeyHandler = { [weak self] key in self?.popup.handleKey(key) ?? false }

        startKeyTap()
    }

    // MARK: Pasting

    private func paste(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            if let rtf = item.rtf { pasteboard.setData(rtf, forType: .rtf) }
            pasteboard.setString(item.text ?? "", forType: .string)
        case .image:
            guard let data = store.imageData(for: item) else { return }
            pasteboard.setData(data, forType: .png)
            if let tiff = NSImage(data: data)?.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        }
        monitor.ignoreCurrentContents()
        store.promote(item)

        // Give the popup a moment to disappear before sending the keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { KeyTap.postPaste() }
    }

    // MARK: Accessibility permission

    private func startKeyTap() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted && keyTap.start() {
            updateMenu()
            return
        }
        updateMenu()
        // Keep checking until the user grants permission in System Settings.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), self.keyTap.start() else { return }
            timer.invalidate()
            self.updateMenu()
        }
    }

    // MARK: Menu bar

    private func setUpMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { updateMenu() }

    private func updateMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        if keyTap.isRunning {
            let hint = NSMenuItem(title: "Hold ⌘V to see history", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        } else {
            menu.addItem(item("Grant Accessibility Permission…", #selector(openAccessibilitySettings)))
        }
        let count = NSMenuItem(title: "\(store.items.count) of \(HistoryStore.maxItems) items saved", action: nil, keyEquivalent: "")
        count.isEnabled = false
        menu.addItem(count)
        menu.addItem(.separator())

        menu.addItem(item("Clear History", #selector(clearHistory)))
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit Clipboard", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func clearHistory() {
        store.clear()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("Clipboard: launch at login change failed: \(error)")
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func setUpLaunchAtLoginOnFirstRun() {
        let key = "didSetUpLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
