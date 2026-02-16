# <img src="icon.svg" width="28" height="28" alt="icon" /> FourFingerTap

**Turn your Mac trackpad into a power tool — map a quick 4-finger tap to any action.**

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-black?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.7+-F05138?logo=swift&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Status](https://img.shields.io/badge/Status-Stable-green)

---

FourFingerTap is a lightweight macOS menu bar utility that listens for **4-finger taps** on your trackpad and fires a configurable action — a middle click, a keyboard shortcut, or a system command. It uses intelligent filtering (duration + movement) to cleanly separate intentional taps from swipes, pinches, and other gestures, so your existing 3-finger and 4-finger swipe gestures continue working perfectly.

## Why?

Mac trackpads don't have a middle mouse button. That means you can't:

- **Middle-click a link** to open it in a new tab
- **Middle-click a tab** to close it
- **Middle-click paste** in a terminal
- Trigger any of the dozens of middle-click actions that power users rely on daily

Plugging in a mouse just for middle-click is silly. FourFingerTap solves this with a natural gesture you can learn in 10 seconds.

## Demo

> Tap the trackpad with 4 fingers → action fires instantly.
>
> Swipe with 4 fingers → nothing happens (gesture passes through to macOS).

| Gesture | Result |
|---|---|
| Quick 4-finger tap (~60–100ms) | ✅ Fires your configured action |
| 4-finger swipe (Mission Control, Spaces) | ❌ Ignored — passes through to macOS |
| 4-finger pinch (Launchpad) | ❌ Ignored — passes through to macOS |
| 3-finger gestures | ❌ Completely unaffected |
| Long 4-finger press | ❌ Ignored (exceeds tap duration) |

## Installation

### Prerequisites

- **macOS 12 (Monterey)** or later
- **Xcode Command Line Tools**:
  ```bash
  xcode-select --install
  ```
- **Optional** (for app icon generation from SVG):
  ```bash
  brew install librsvg
  ```

### Build from Source

```bash
git clone https://github.com/YOUR_USERNAME/FourFingerTap.git
cd FourFingerTap
chmod +x build.sh
./build.sh
```

### Install

```bash
cp -r build/FourFingerTap.app /Applications/
open /Applications/FourFingerTap.app
```

### Grant Accessibility Permission

On first launch, you'll be prompted to grant Accessibility access. This is required so the app can simulate mouse clicks and keystrokes.

1. Click **"Open System Settings"** when prompted
2. Toggle **FourFingerTap** to **ON** in:

   `System Settings → Privacy & Security → Accessibility`

3. The app starts working immediately — no relaunch needed.

> **Why does it need this?** FourFingerTap uses `CGEvent` to post synthetic mouse/keyboard events at the system level. macOS requires explicit Accessibility permission for any app that does this. The app has zero network access and never collects or transmits any data.

### Start at Login (Optional)

To have FourFingerTap launch automatically:

`System Settings → General → Login Items → click + → select FourFingerTap`

## Configuration

Everything is configurable from the menu bar icon. Click the trackpad icon (four dots over a trackpad) to open the menu.

### Tap Action

Choose what happens when you 4-finger tap:

| Category | Actions |
|---|---|
| **Mouse** | Middle Click · Right Click |
| **Browser** | Close Tab `⌘W` · New Tab `⌘T` · Reopen Closed Tab `⇧⌘T` · Refresh `⌘R` |
| **Edit** | Copy `⌘C` · Paste `⌘V` · Undo `⌘Z` |
| **System** | Mission Control · Launchpad · Spotlight `⌘Space` |

The default action is **Middle Click** — the most common use case.

### Tap Duration

Controls the maximum time your fingers can be on the trackpad for the gesture to count as a "tap" rather than a hold or the beginning of a swipe.

| Setting | Value | Best For |
|---|---|---|
| Very fast tap only | 80ms | Avoiding false positives at all costs |
| Fast tap | 100ms | Experienced users with quick reflexes |
| **Default** | **120ms** | **Most users — excellent balance** |
| Comfortable | 150ms | Slightly more forgiving |
| Relaxed | 200ms | Users who prefer a deliberate tap |
| Generous | 250ms | Very forgiving timing |
| Very generous | 350ms | Maximum tolerance |

> **How it works:** A real tap takes 30–100ms. A swipe takes 200–500ms. By defaulting to 120ms, the app rejects virtually all swipes/pinches by duration alone, while catching all intentional taps.

### Movement Tolerance

Controls how much your fingers can move during the tap before it's rejected as a swipe or pinch. Measured in millimeters of finger travel on the trackpad surface.

| Setting | Value | Description |
|---|---|---|
| Strict | ~1.5mm | Fingers must be nearly still |
| **Default** | **~3mm** | **Allows natural finger jitter** |
| Loose | ~5mm | More forgiving |
| Very Loose | ~8mm | Quite forgiving |
| Disabled | — | No movement check |

> **How it works:** On every frame while 4 fingers are down, the app reads the centroid (average position) of all fingers and compares it to where they first landed. If the centroid drifts beyond the threshold, the gesture is rejected. This is what prevents 4-finger swipes from triggering.

### All preferences persist across restarts.

## How It Works

FourFingerTap operates at a level below macOS gestures, which is why it can coexist with system trackpad features:

### 1. Raw Multitouch Data

The app loads Apple's private `MultitouchSupport.framework` at runtime via `dlopen`. This framework provides frame-by-frame multitouch contact data directly from the trackpad hardware — before macOS processes it into gestures.

A callback fires ~60–100 times per second with the number of fingers currently touching the trackpad.

### 2. Tap Detection

When exactly **4 fingers** are detected:
- The app records the **start time** and **finger centroid position**
- On every subsequent frame, it tracks the **maximum finger count** and **centroid drift**
- When fingers lift below 4, it evaluates the gesture:

```
✅ Accept if:
   duration > 20ms          (not a phantom touch)
   duration < threshold      (default 120ms — fast enough to be a tap)
   max fingers == 4          (exactly 4, not 5 passing through)
   centroid drift < tolerance (default 3mm — didn't swipe)

❌ Reject otherwise → gesture passes through to macOS
```

### 3. Auto-Detected Struct Layout

The `MTTouch` struct layout varies across macOS versions. Rather than hardcoding offsets, the app auto-detects the struct stride on the first multi-finger frame by scanning candidate sizes (64–128 bytes) and validating that the second finger's normalized coordinates fall in the expected 0.0–1.0 range.

### 4. Event Simulation

When a valid tap is detected, the app uses `CGEvent` to post synthetic events:

- **Mouse actions** → `otherMouseDown` / `otherMouseUp` at the current cursor position (read directly from `CGEvent` coordinate space to avoid Cocoa→CG conversion bugs)
- **Keyboard shortcuts** → `keyDown` / `keyUp` with appropriate modifier flags
- Events are posted at the HID level (`.cghidEventTap`) for broadest app compatibility

## Debugging

Run from Terminal to see live touch events:

```bash
/Applications/FourFingerTap.app/Contents/MacOS/FourFingerTap
```

Enable **Debug Logging** from the menu bar, then tap the trackpad:

```
👆 4-finger touch started at (0.450, 0.520)
✅ TAP! 67ms, moved 0.0042 → Middle Click
🖱️ Middle-click at (834, 502)
```

Rejected gestures show the reason:

```
❌ Rejected: 312ms, moved 0.1820, max fingers 4 — duration(312ms), movement(0.1820)
```

Use the **"Test Action (2s delay)"** button to verify event posting works independently of touch detection.

## Troubleshooting

### Taps aren't detected at all

1. **Check Accessibility permission** is granted in System Settings
2. **Run from Terminal** with debug logging to verify the multitouch device is found:
   ```
   ✅ Device 0: started
   📱 Monitoring 1/1 device(s)
   ```
3. Use **"Restart Touch Detection"** from the menu

### Taps are inconsistent

- Try increasing **Tap Duration** to "Comfortable (150ms)" or "Relaxed (200ms)"
- Try increasing **Movement Tolerance** to "Loose (5mm)"
- Run with debug logging to see why taps are being rejected

### 4-finger swipes also trigger the action

- **Decrease** Tap Duration to "Fast tap (100ms)" or "Very fast (80ms)"
- **Decrease** Movement Tolerance to "Strict (1.5mm)"
- The defaults (120ms / 3mm) should work for most people

### "Test Action" works but 4-finger tap doesn't

This means event posting is fine but touch detection has an issue:
- Check debug logs for touch events
- Try **"Restart Touch Detection"**
- Close and reopen the app

## Creating a DMG for Distribution

```bash
./build.sh            # Build the app
./package_dmg.sh      # Create FourFingerTap-2.1.dmg
```

See [DISTRIBUTION.md](DISTRIBUTION.md) for instructions on notarization, Homebrew Cask, and other distribution options.

> **Note:** This app cannot be published on the Mac App Store because it uses Apple's private `MultitouchSupport.framework` and requires Accessibility access outside the App Store sandbox. This is the same reason utilities like BetterTouchTool and Karabiner-Elements distribute outside the store.

## Project Structure

```
FourFingerTap/
├── Sources/
│   └── main.swift            # Complete app in a single file (~500 lines)
├── Info.plist                # App bundle metadata
├── icon.svg                  # App icon source (4 dots + trackpad)
├── build.sh                  # Build: icon generation + compile + bundle
├── package_dmg.sh            # Create distributable .dmg
├── generate_icon.sh          # Standalone SVG → .icns converter
├── DISTRIBUTION.md           # Distribution & notarization guide
├── LICENSE                   # MIT License
├── .gitignore
└── README.md
```

The entire app is a single Swift file with zero dependencies beyond macOS system frameworks. No Xcode project, no Swift packages, no CocoaPods.

## Requirements

| | Minimum |
|---|---|
| macOS | 12.0 (Monterey) |
| Hardware | Any Mac with a Force Touch or pre-Force Touch trackpad |
| Build tools | Xcode Command Line Tools |
| Runtime permissions | Accessibility |
| Network access | None (fully offline) |

## Contributing

Contributions are welcome! Some ideas:

- **More actions** — add new actions to the `TapAction` enum (e.g., screenshot, do not disturb, volume mute)
- **Configurable finger count** — let users choose 3, 4, or 5 finger taps
- **Multiple gesture mappings** — different actions for different finger counts
- **Sparkle integration** — auto-update framework
- **SwiftUI settings window** — richer configuration UI than a menu

## License

MIT — free to use, modify, and distribute.