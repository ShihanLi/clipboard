# Clipboard

A tiny macOS clipboard history that lives behind the shortcut you already use.

- **Tap ⌘V** – pastes normally.
- **Hold ⌘V** (~0.4s) – a history popup opens next to your mouse. Click an item to paste it.

## Features

- Remembers your last 50 copies — text (including rich text) and images
- Saved locally, survives restarts; copying something again moves it to the top instead of duplicating it
- Skips passwords and other items password managers mark as secret ([nspasteboard.org](http://nspasteboard.org) markers)
- Keyboard friendly popup: ↑/↓ + Return, or 1–9 for the first nine items; Esc or click outside to close
- Menu bar icon with Clear History, Launch at Login, and Quit — no Dock icon
- No dependencies, no network access, ~700 lines of Swift

## Install

Requires macOS 13 or later and Xcode (or the Xcode Command Line Tools).

```sh
git clone https://github.com/ShihanLi/clipboard.git
cd clipboard
./build.sh --install
```

This builds `Clipboard.app`, copies it to `/Applications`, and launches it.

Then grant permission: **System Settings → Privacy & Security → Accessibility → turn on Clipboard**.
It's needed to intercept ⌘V and to paste on your behalf. The app starts working within a couple of seconds of granting it.

> **Note:** If you have an Apple Development certificate in your keychain, the build is signed with it and the permission persists across rebuilds. Otherwise the app is ad-hoc signed and macOS may ask you to re-grant Accessibility after each rebuild (remove the old entry and add it again).

## How it works

| File | What it does |
| --- | --- |
| `Sources/KeyTap.swift` | A `CGEventTap` that swallows ⌘V. Released before the threshold → posts a normal ⌘V; held past it → opens the popup. |
| `Sources/PasteboardMonitor.swift` | Polls `NSPasteboard` for changes and records new text/images. |
| `Sources/History.swift` | Stores history in `~/Library/Application Support/Clipboard/` (JSON + PNGs). |
| `Sources/Popup.swift` | A non-activating floating panel, so the app you're pasting into keeps focus. |
| `Sources/main.swift` | App setup, menu bar, and pasting a chosen item. |

Tweak the hold length with `holdThreshold` in `KeyTap.swift`, or the history size with `maxItems` in `History.swift`.

## Limitations

- In secure text fields (password boxes) macOS blocks keyboard monitoring, so ⌘V there is always a plain paste.
- Files copied in Finder aren't recorded.
- Holding ⌘V no longer repeat-pastes.

## Uninstall

Quit from the menu bar icon, then:

```sh
rm -rf /Applications/Clipboard.app ~/Library/Application\ Support/Clipboard
```

## License

MIT
