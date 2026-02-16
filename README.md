# <img src="icon.svg" width="28" height="28" alt="icon" /> Mac Gesture

**Custom trackpad gestures for macOS — starting with the missing middle click.**

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-black?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.7+-F05138?logo=swift&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Build](https://github.com/is-harshul/mac-gesture/actions/workflows/release.yml/badge.svg)
![GitHub Release](https://img.shields.io/github/v/release/is-harshul/mac-gesture?label=Latest)

---

## ⬇️ Download

**[Download Latest Release (DMG)](https://github.com/is-harshul/mac-gesture/releases/latest)**

> Open the DMG → drag **MacGesture.app** into **Applications** → launch → grant Accessibility permission → done.
>
> If macOS shows an "unidentified developer" warning: **right-click the app → Open → Open**.

A new DMG is built and published automatically on every push to `main`.

---

## The Problem

Mac trackpads don't have a middle mouse button. That means you can't:

- **Middle-click a link** to open it in a new browser tab
- **Middle-click a tab** to close it
- **Middle-click paste** in a terminal
- Trigger any of the dozens of middle-click actions that power users rely on

Plugging in a mouse just for middle-click is absurd. Mac Gesture gives you a natural 4-finger tap gesture you can learn in 10 seconds.

---

## How It Works

> **Quick 4-finger tap on trackpad → your chosen action fires instantly.**

Mac Gesture distinguishes taps from other gestures using two filters:

| Check | What it does | Default |
|---|---|---|
| **Duration** | Rejects anything held too long (swipes, pinches, holds) | ≤ 120ms |
| **Movement** | Rejects if fingers drift (swipe/pinch motion detected) | ≤ 3mm |

Real taps are 30–100ms with almost no finger movement. Swipes are 200ms+ with significant drift. The combination catches all taps and rejects everything else.

| Gesture | Result |
|---|---|
| Quick 4-finger tap (~60–100ms) | ✅ Fires your configured action |
| 4-finger swipe (Mission Control, Spaces) | ❌ Ignored — passes through to macOS |
| 4-finger pinch (Launchpad) | ❌ Ignored — passes through to macOS |
| 3-finger gestures (drag, etc.) | ❌ Completely unaffected |
| Long 4-finger press | ❌ Ignored (exceeds tap duration) |

---

## Installation

### Prerequisites

- **macOS 12 (Monterey)** or later
- **Xcode Command Line Tools**:
  ```bash
  xcode-select --install
  ```
- *Optional* — for app icon generation from SVG:
  ```bash
  brew install librsvg
  ```

### Build from Source

```bash
git clone https://github.com/is-harshul/mac-gesture.git
cd mac-gesture
chmod +x build.sh
./build.sh
cp -r build/MacGesture.app /Applications/
open /Applications/MacGesture.app
```

### Grant Accessibility Permission

On first launch, you'll be prompted to grant Accessibility access:

1. Click **"Open System Settings"** when prompted
2. In **System Settings → Privacy & Security → Accessibility**, toggle **MacGesture** to **ON**
3. The app starts working immediately — no relaunch needed

> **Why?** Mac Gesture uses `CGEvent` to post synthetic mouse/keyboard events at the system level. macOS requires explicit Accessibility permission for this. The app has zero network access and never collects or transmits any data.

### Start at Login (Optional)

`System Settings → General → Login Items → click + → select MacGesture`

---

## Configuration

Click the trackpad icon in the menu bar to access all settings.

### Tap Action

Choose what happens when you 4-finger tap:

| Category | Actions |
|---|---|
| **Mouse** | Middle Click · Right Click |
| **Browser** | Close Tab `⌘W` · New Tab `⌘T` · Reopen Closed Tab `⇧⌘T` · Refresh `⌘R` |
| **Edit** | Copy `⌘C` · Paste `⌘V` · Undo `⌘Z` |
| **System** | Mission Control · Launchpad · Spotlight `⌘Space` |

Default: **Middle Click**.

### Tap Duration (max)

How long fingers can stay on the trackpad and still count as a "tap":

| Setting | Value | Best For |
|---|---|---|
| Very fast | 80ms | Avoiding false positives at all costs |
| Fast | 100ms | Quick reflexes |
| **Default** | **120ms** | **Most users** |
| Comfortable | 150ms | Slightly more forgiving |
| Relaxed | 200ms | Deliberate tappers |
| Generous | 250ms | Very forgiving |
| Very generous | 350ms | Maximum tolerance |

### Movement Tolerance

How much finger drift is allowed before the gesture is rejected as a swipe/pinch:

| Setting | Value | Description |
|---|---|---|
| Strict | ~1.5mm | Fingers must be nearly still |
| **Default** | **~3mm** | **Allows natural jitter** |
| Loose | ~5mm | More forgiving |
| Very Loose | ~8mm | Quite forgiving |
| Disabled | — | No movement check |

All preferences persist across app restarts.

---

## Under the Hood

### 1. Raw Multitouch Data

Mac Gesture loads Apple's private `MultitouchSupport.framework` via `dlopen` at runtime. This provides frame-by-frame (~60–100 fps) multitouch contact data directly from the trackpad hardware — *before* macOS processes it into system gestures.

### 2. Tap Detection Algorithm

```
When exactly 4 fingers land:
  → Record start time + finger centroid position
  → Track max finger count + centroid drift each frame

When fingers lift below 4:
  ✅ Accept if ALL of:
     • duration > 20ms          (not a phantom touch)
     • duration < threshold      (default 120ms — too fast to be a swipe)
     • max fingers == 4          (exactly 4, not 5 passing through)
     • centroid drift < tolerance (default 3mm — fingers didn't travel)
  ❌ Reject otherwise → gesture passes through to macOS untouched
```

### 3. Auto-Detected Struct Layout

The internal `MTTouch` struct layout varies across macOS versions. Rather than hardcoding byte offsets, the app auto-detects the struct stride by scanning candidate sizes (64–128 bytes) and validating that the second finger's normalized coordinates fall in the expected 0.0–1.0 range.

### 4. Event Simulation

Valid taps trigger `CGEvent` posts at the HID level:

- **Mouse actions** → `otherMouseDown` / `otherMouseUp` at the cursor position (read directly from CG coordinate space)
- **Keyboard shortcuts** → `keyDown` / `keyUp` with modifier flags
- Posted at `.cghidEventTap` for broadest app compatibility

---

## Debugging

Run from Terminal to see live touch events:

```bash
/Applications/MacGesture.app/Contents/MacOS/MacGesture
```

Enable **Debug Logging** from the menu bar:

```
👆 4-finger touch started at (0.450, 0.520)
✅ TAP! 67ms, moved 0.0042 → Middle Click
🖱️ Middle-click at (834, 502)
```

Rejected gestures show exactly why:

```
❌ Rejected: 312ms, moved 0.1820, max fingers 4 — duration(312ms), movement(0.1820)
```

Use **"Test Action (2s delay)"** from the menu to verify event posting works independently of touch detection.

---

## Troubleshooting

### Taps aren't detected at all
- Verify **Accessibility permission** is granted
- Run from Terminal and check device detection: `✅ Device 0: started`
- Use **"Restart Touch Detection"** from the menu

### Taps are inconsistent
- Increase **Tap Duration** to "Comfortable (150ms)" or "Relaxed (200ms)"
- Increase **Movement Tolerance** to "Loose (5mm)"
- Use debug logging to see why taps are rejected

### 4-finger swipes also trigger the action
- Decrease **Tap Duration** to "Fast (100ms)" or "Very fast (80ms)"
- Decrease **Movement Tolerance** to "Strict (1.5mm)"

### "Test Action" works but 4-finger tap doesn't
- Event posting is fine; the issue is touch detection
- Check debug logs → try **"Restart Touch Detection"**

---

## Distribution

```bash
./release.sh          # Builds app + creates DMG
```

See [DISTRIBUTION.md](DISTRIBUTION.md) for notarization and Homebrew Cask options.

> This app cannot be published on the Mac App Store — it uses Apple's private `MultitouchSupport.framework` and requires Accessibility access outside the sandbox.

---

## CI/CD

Every push to `main` triggers a [GitHub Actions workflow](.github/workflows/release.yml) that:

1. Runs `./release.sh` (builds app + creates DMG)
2. Reads version from `Info.plist`
3. Creates a GitHub Release with the DMG attached

To publish a new version: bump the version in `Info.plist` and push to `main`. That's it.

If the release tag already exists (same version, code fix), the workflow replaces the DMG on the existing release.

---

## Project Structure

```
mac-gesture/
├── .github/
│   └── workflows/
│       └── release.yml       # CI: runs release.sh on push to main
├── Sources/
│   └── main.swift            # Complete app (~730 lines, zero dependencies)
├── Info.plist                # App bundle metadata + version
├── icon.svg                  # App icon (4 dots + trackpad)
├── build.sh                  # Compile + icon generation + .app bundle
├── release.sh                # build.sh + DMG packaging
├── package_dmg.sh            # .dmg with drag-to-Applications
├── generate_icon.sh          # Standalone SVG → .icns converter
├── DISTRIBUTION.md           # Notarization & distribution guide
├── LICENSE                   # MIT
├── .gitignore
└── README.md
```

Single Swift file. No Xcode project. No package manager. No external dependencies.

---

## Requirements

| | Minimum |
|---|---|
| macOS | 12.0 (Monterey) |
| Hardware | Any Mac with a trackpad |
| Build tools | Xcode Command Line Tools |
| Runtime | Accessibility permission |
| Network | None (fully offline) |

---

## Contributing

Contributions welcome! Ideas:

- **More actions** — screenshot, do not disturb, volume mute, lock screen
- **Configurable finger count** — 3, 4, or 5 finger taps
- **Multiple gesture mappings** — different actions for different finger counts
- **Double-tap detection** — two quick 4-finger taps for a different action
- **SwiftUI settings window** — richer UI than a menu

---

## License

[MIT](LICENSE) — free to use, modify, and distribute.
