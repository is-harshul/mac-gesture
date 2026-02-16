# MacGesture — Distribution Guide

## ⚠️ Why the Mac App Store Won't Work

MacGesture **cannot be distributed via the Mac App Store** due to two hard blockers:

1. **Private Framework Usage** — The app uses Apple's private `MultitouchSupport.framework` to read raw trackpad touch data. Apple rejects apps that use private frameworks.

2. **Sandboxing Incompatibility** — App Store apps must be sandboxed. MacGesture needs Accessibility API access and `CGEvent` posting at the HID level, both blocked inside the sandbox.

This is the same reason BetterTouchTool, Karabiner-Elements, and similar utilities distribute outside the store.

---

## ✅ Distribution Options

### Option 1: GitHub Releases (Current Setup)

Every push to `main` automatically builds a DMG via GitHub Actions and publishes it as a release.

Users download from: **https://github.com/is-harshul/mac-gesture/releases/latest**

**Pros:** Fully automated, free.
**Cons:** Users get a Gatekeeper warning on first launch (right-click → Open).

---

### Option 2: Notarized Distribution (No Gatekeeper Warning)

**Requirements:** Apple Developer account ($99/year)

```bash
# Sign with hardened runtime
codesign --force --deep --options runtime \
    --sign "Developer ID Application: YOUR NAME (TEAM_ID)" \
    build/MacGesture.app

# Create and sign DMG
./package_dmg.sh
codesign --force \
    --sign "Developer ID Application: YOUR NAME (TEAM_ID)" \
    build/MacGesture-2.2.dmg

# Submit for notarization
xcrun notarytool submit build/MacGesture-2.2.dmg \
    --apple-id "your@email.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "app-specific-password" \
    --wait

# Staple the ticket
xcrun stapler staple build/MacGesture-2.2.dmg
```

Now users can double-click to install with zero warnings.

---

### Option 3: Homebrew Cask

```bash
# Get SHA256
shasum -a 256 build/MacGesture-2.2.dmg
```

Create `Casks/mac-gesture.rb`:
```ruby
cask "mac-gesture" do
  version "2.2"
  sha256 "YOUR_SHA256_HERE"

  url "https://github.com/is-harshul/mac-gesture/releases/download/v#{version}/MacGesture-#{version}.dmg"
  name "MacGesture"
  desc "4-finger trackpad tap to simulate middle-click and other actions"
  homepage "https://github.com/is-harshul/mac-gesture"

  app "MacGesture.app"

  zap trash: [
    "~/Library/Preferences/com.macgesture.app.plist",
  ]
end
```

Users install with: `brew install --cask is-harshul/tap/mac-gesture`

---

## Summary

| Method | Cost | User Experience | Effort |
|---|---|---|---|
| **GitHub Releases** | **Free** | **Right-click → Open on first launch** | **Automated (CI)** |
| Notarized DMG | $99/yr | Seamless, no warnings | Manual signing |
| Homebrew Cask | Free + notarization | `brew install` | Cask formula |
| Mac App Store | N/A | Not possible | N/A |
