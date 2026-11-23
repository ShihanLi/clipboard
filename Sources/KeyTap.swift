import AppKit

/// Marks keystrokes this app posts itself so the tap lets them through.
let syntheticEventMarker: Int64 = 0x434C_4950 // "CLIP"

private let keyV: Int64 = 9

/// Watches the keyboard for Cmd+V.
/// A quick tap pastes when the key is released; holding past the threshold opens the popup.
final class KeyTap {
    var holdThreshold: TimeInterval = 0.4

    /// Called when Cmd+V has been held past the threshold.
    var onHold: () -> Void = {}
    /// While the popup is visible, key presses go here first. Return true to swallow the key.
    var popupKeyHandler: ((Int64) -> Bool)?
    var isPopupVisible: () -> Bool = { false }

    private var tap: CFMachPort?
    private var vIsDown = false
    private var popupOpenedForThisPress = false
    private var holdTimer: Timer?

    var isRunning: Bool { tap != nil }

    /// Returns false if the tap can't be created (Accessibility permission missing).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                let me = Unmanaged<KeyTap>.fromOpaque(userInfo!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker {
            return pass
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])

        if keyCode == keyV {
            if type == .keyDown {
                if vIsDown { return nil }                    // auto-repeat while held
                if modifiers == .maskCommand {
                    if isPopupVisible() { return nil }       // already showing
                    beginPress()
                    return nil
                }
            } else if type == .keyUp, vIsDown {
                endPress()
                return nil
            }
        }

        if type == .keyDown, isPopupVisible(), let handler = popupKeyHandler {
            if handler(keyCode) { return nil }
        }
        return pass
    }

    private func beginPress() {
        vIsDown = true
        popupOpenedForThisPress = false
        let timer = Timer(timeInterval: holdThreshold, repeats: false) { [weak self] _ in
            guard let self, self.vIsDown else { return }
            self.popupOpenedForThisPress = true
            self.onHold()
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func endPress() {
        vIsDown = false
        holdTimer?.invalidate()
        holdTimer = nil
        if !popupOpenedForThisPress {
            KeyTap.postPaste()
        }
    }

    /// Sends a Cmd+V keystroke to the frontmost app.
    static func postPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.userData = syntheticEventMarker
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyV), keyDown: isDown) else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}
