# FourFingerTap

**Map a 4-finger trackpad tap to any action on macOS.**

A lightweight menu bar utility that detects quick 4-finger taps on your Mac trackpad and triggers a configurable action — middle click, keyboard shortcuts, or system functions. Taps are cleanly separated from swipes and pinches using both duration and movement filtering.

## Quick Start

```bash
# Build
chmod +x build.sh
./build.sh

# Install
cp -r build/FourFingerTap.app /Applications/

# Run
open /Applications/FourFingerTap.app
```

Grant **Accessibility permission** when prompted (System Settings → Privacy & Security → Accessibility).

## Features

### 12 Configurable Actions

| Category | Actions |
|---|---|
| **Mouse** | Middle Click, Right Click |
| **Browser** | Close Tab (⌘W), New Tab (⌘T), Reopen Closed Tab (⇧⌘T), Refresh (⌘R) |
| **Edit** | Copy (⌘C), Paste (⌘V), Undo (⌘Z) |
| **System** | Mission Control, Launchpad, Spotlight (⌘Space) |

### Smart Tap Detection

Distinguishes taps from swipes and pinches using two filters:

- **Duration filter** — Default 120ms max. Real taps are 30–100ms; swipes/pinches are 200ms+.
- **Movement filter** — Tracks finger centroid position. If fingers move more than ~3mm, it's rejected as a swipe/pinch.

Both thresholds are user-configurable from the menu bar.

### Preferences Persist

Your selected action, tap duration, and movement tolerance are saved across app restarts.

## Configuration

Click the trackpad icon in the menu bar to access all settings:

- **Tap Action** — Choose what happens on 4-finger tap
- **Tap Duration** — 80ms (strict) to 350ms (generous)
- **Movement Tolerance** — 1.5mm (strict) to disabled
- **Test Action** — Fires the action after 2 seconds to verify it works
- **Debug Logging** — See every touch event in Terminal

## Distribution

This app uses Apple's private `MultitouchSupport.framework` and cannot be published on the Mac App Store. See [DISTRIBUTION.md](DISTRIBUTION.md) for instructions on:

- Direct DMG sharing
- Notarized distribution (no Gatekeeper warnings)
- Homebrew Cask
- GitHub Releases

## Project Structure

```
FourFingerTap/
├── Sources/main.swift       # Complete app source
├── Info.plist               # App bundle config
├── icon.svg                 # App icon source (1024x1024 SVG)
├── generate_icon.sh         # SVG → .icns converter
├── build.sh                 # Build script (icon + compile + bundle)
├── package_dmg.sh           # Create distributable .dmg
├── DISTRIBUTION.md          # Distribution guide
└── README.md
```

## Requirements

- macOS 12 (Monterey) or later
- Xcode Command Line Tools (`xcode-select --install`)
- Optional: `brew install librsvg` (for icon generation from SVG)

## License

MIT
