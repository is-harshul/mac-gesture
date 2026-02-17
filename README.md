# <img src="icon.svg" width="28" height="28" alt="icon" /> Mac Gesture

**Custom trackpad gestures for macOS — map 3, 4, and 5-finger taps to any action.**

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

Mac trackpads are incredible hardware with terrible gesture support. You can't middle-click, you can't map multi-finger taps to custom actions, and Apple gives you no way to fix this.

Mac Gesture lets you assign **any action** to a **3-finger tap**, **4-finger tap**, or **5-finger tap** — independently configurable, with smart tap detection that doesn't interfere with your existing swipe/pinch gestures.

---

## How It Works

| Gesture | Default | Configurable? |
|---|---|---|
| 3-finger tap | Disabled | ✅ |
| 4-finger tap | Middle Click | ✅ |
| 5-finger tap | Disabled | ✅ |
| 3/4/5-finger swipe | Passes through to macOS | — |
| 3/4/5-finger pinch | Passes through to macOS | — |

Mac Gesture distinguishes taps from other gestures using duration (≤120ms default) and movement (≤3mm default) filters. Your existing macOS swipe, pinch, and drag gestures are completely unaffected.

---

## Available Actions

Each finger count can be independently assigned to any of these:

| Category | Actions |
|---|---|
| **Off** | Disabled |
| **Mouse** | Middle Click · Right Click |
| **Browser** | Close Tab `⌘W` · New Tab `⌘T` · Reopen Closed Tab `⇧⌘T` · Refresh `⌘R` |
| **Edit** | Copy `⌘C` · Paste `⌘V` · Undo `⌘Z` |
| **System** | Mission Control · Launchpad · Spotlight `⌘Space` |

**Example setup:** 3-finger tap → Copy, 4-finger tap → Middle Click, 5-finger tap → Mission Control.

---

## Installation

### Download

Grab the DMG from [Releases](https://github.com/is-harshul/mac-gesture/releases/latest), or build from source:

```bash
git clone https://github.com/is-harshul/mac-gesture.git
cd mac-gesture
chmod +x build.sh
./build.sh
cp -r build/MacGesture.app /Applications/
open /Applications/MacGesture.app
```

### Grant Accessibility Permission

On first launch:

1. Click **"Open System Settings"** when prompted
2. Toggle **MacGesture** to **ON** in **System Settings → Privacy & Security → Accessibility**

> The app uses `CGEvent` to simulate mouse/keyboard events. It has zero network access and collects no data.

### Start at Login

`System Settings → General → Login Items → + → select MacGesture`

---

## Configuration

Click the trackpad icon in the menu bar. The menu shows three gesture sections:

```
MacGesture
  3F → Disabled
  4F → Middle Click
─────────────────────
✓ Enabled
─────────────────────
3-FINGER TAP  Off
  ○ Disabled (Off)
    Mouse
  ○ Middle Click
  ○ Right Click
    Browser
  ○ Close Tab  (⌘W)
  ...
─────────────────────
4-FINGER TAP  Middle Click
  ○ Disabled (Off)
    Mouse
  ● Middle Click
  ...
─────────────────────
5-FINGER TAP  Off
  ...
─────────────────────
Tap Duration (max) ▸
Movement Tolerance ▸
```

### Tap Duration

| Setting | Value | Notes |
|---|---|---|
| Very fast | 80ms | Strict |
| **Default** | **120ms** | **Most users** |
| Relaxed | 200ms | More forgiving |
| Very generous | 350ms | Maximum tolerance |

### Movement Tolerance

| Setting | Value |
|---|---|
| Strict | ~1.5mm |
| **Default** | **~3mm** |
| Loose | ~5mm |
| Disabled | No check |

Settings apply to all gesture types and persist across restarts.

---

## Tap Detection

The gesture recognizer uses peak finger count to avoid ghost triggers:

1. **3+ fingers land** → start tracking time and finger centroid
2. **While fingers are down** → track peak finger count and centroid drift
3. **All fingers lift** → evaluate based on peak count:
   - Duration between 20ms and threshold? ✓
   - Centroid movement below tolerance? ✓
   - Peak finger count has a configured action? ✓
   - All three pass → fire the action

By evaluating only when **all fingers lift** (count == 0), a 5-finger tap can't accidentally trigger the 4-finger or 3-finger action on the way down.

---

## Debugging

```bash
/Applications/MacGesture.app/Contents/MacOS/MacGesture
```

Enable **Debug Logging** from the menu:

```
👆 4-finger touch started at (0.450, 0.520)
✅ 4-FINGER TAP! 67ms, moved 0.0042 → Middle Click
🖱️ Middle-click at (834, 502)

👆 3-finger touch started at (0.320, 0.610)
❌ Rejected 3F: 45ms, moved 0.0012 — 3F not configured

👆 5-finger touch started at (0.500, 0.500)
❌ Rejected 5F: 312ms, moved 0.1820 — duration(312ms), movement(0.1820)
```

---

## Troubleshooting

**Taps not detected** — Check Accessibility permission. Run from Terminal to see device detection logs.

**Taps inconsistent** — Increase Tap Duration to 150–200ms and/or Movement Tolerance to 5mm.

**Swipes triggering actions** — Decrease Tap Duration to 80–100ms and/or Movement Tolerance to 1.5mm.

**3-finger tap interferes with macOS drag** — If you use 3-finger drag (System Settings → Accessibility → Pointer Control → Trackpad Options), the 3-finger gesture may conflict. Either disable 3-finger tap in Mac Gesture or switch macOS to use a different drag method.

---

## CI/CD

Every push to `main` triggers a [GitHub Actions workflow](.github/workflows/release.yml) that builds the app, creates a DMG, and publishes a GitHub Release. To ship a new version: bump the version in `Info.plist` and push.

---

## Project Structure

```
mac-gesture/
├── .github/workflows/release.yml   # CI: build + release on push to main
├── Sources/main.swift               # Complete app (~760 lines)
├── Info.plist                       # Bundle metadata + version
├── icon.svg                         # App icon
├── build.sh                         # Compile + icon + .app bundle
├── release.sh                       # build.sh + DMG
├── package_dmg.sh                   # DMG packaging
├── generate_icon.sh                 # SVG → .icns
├── DISTRIBUTION.md                  # Notarization & Homebrew guide
├── LICENSE
├── .gitignore
└── README.md
```

Single Swift file. No Xcode project. No package manager. No external dependencies.

---

## Contributing

Ideas: more actions (screenshot, DnD toggle, volume mute, lock screen), configurable finger counts beyond 3–5, double-tap detection, SwiftUI settings window.

## License

[MIT](LICENSE)
