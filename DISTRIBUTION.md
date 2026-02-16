# MacGesture — Distribution Guide

## ⚠️ Why the Mac App Store Won't Work

MacGesture **cannot be distributed via the Mac App Store** due to two hard blockers:

1. **Private Framework Usage** — The app uses Apple's private `MultitouchSupport.framework` to read raw trackpad touch data. Apple automatically rejects any app that uses private frameworks.

2. **Sandboxing Incompatibility** — App Store apps must be sandboxed. MacGesture needs:
   - Accessibility API access (`AXIsProcessTrusted`) to post synthetic events
   - `CGEvent` posting at the HID level to simulate clicks/keystrokes
   - Both are blocked inside the App Store sandbox.

This is the same reason popular Mac utilities like **BetterTouchTool**, **Karabiner-Elements**, **Hammerspoon**, and **Magnet** either aren't on the App Store or have reduced functionality there.

---

## ✅ Recommended Distribution Options

### Option 1: Direct Distribution (Simplest)

Share the `.dmg` file directly via your website, GitHub Releases, Google Drive, etc.

```bash
./build.sh
./package_dmg.sh
# → build/MacGesture-2.2.dmg
```

**Pros:** Easy, no Apple Developer account needed.
**Cons:** Users get a Gatekeeper warning ("unidentified developer") and must right-click → Open.

---

### Option 2: Notarized Distribution (Recommended)

Notarization tells macOS "Apple scanned this and it's safe." Users can double-click to install without any warnings.

**Requirements:**
- Apple Developer account ($99/year) — https://developer.apple.com/programs/
- Xcode (full version, not just CLI tools)

**Steps:**

#### 1. Create a Developer ID certificate

```bash
# In Xcode: Xcode → Settings → Accounts → Manage Certificates
# Create a "Developer ID Application" certificate
```

#### 2. Sign the app

```bash
APP="build/MacGesture.app"

# Sign with hardened runtime (required for notarization)
codesign --force --deep --options runtime \
    --sign "Developer ID Application: YOUR NAME (TEAM_ID)" \
    "$APP"

# Verify
codesign --verify --verbose "$APP"
spctl --assess --verbose "$APP"
```

#### 3. Create and sign the DMG

```bash
./package_dmg.sh

codesign --force \
    --sign "Developer ID Application: YOUR NAME (TEAM_ID)" \
    "build/MacGesture-2.2.dmg"
```

#### 4. Notarize with Apple

```bash
# Submit for notarization
xcrun notarytool submit "build/MacGesture-2.2.dmg" \
    --apple-id "your@email.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "app-specific-password" \
    --wait

# Staple the notarization ticket to the DMG
xcrun stapler staple "build/MacGesture-2.2.dmg"
```

> **App-specific password:** Generate one at https://appleid.apple.com → Sign-In and Security → App-Specific Passwords

Now users can double-click to install — no Gatekeeper warnings.

---

### Option 3: Homebrew Cask (Community Distribution)

Once you have a hosted DMG (GitHub Releases is easiest), create a Homebrew Cask:

#### 1. Host the DMG

Upload to GitHub Releases:
```bash
gh release create v2.2 build/MacGesture-2.2.dmg --title "MacGesture 2.2"
```

#### 2. Get the SHA256

```bash
shasum -a 256 build/MacGesture-2.2.dmg
```

#### 3. Create the Cask formula

Create a file `Casks/mac-gesture.rb`:
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

#### 4. Submit to homebrew-cask

Either:
- **Personal tap:** `brew tap is-harshul/tap` → users install with `brew install --cask is-harshul/tap/mac-gesture`
- **Official Homebrew:** Submit a PR to [homebrew-cask](https://github.com/Homebrew/homebrew-cask) (requires notarization + some adoption first)

Then users install with:
```bash
brew install --cask mac-gesture
```

---

### Option 4: GitHub Releases (Most Common for Utilities)

This is what most Mac utilities do:

1. Create a GitHub repo for the project
2. Tag a release: `git tag v2.2 && git push --tags`
3. Upload the DMG to the release
4. Users download from the Releases page

Optional: Add a [Sparkle](https://sparkle-project.org/) update framework so the app can auto-update itself.

---

## Summary

| Method | Cost | User Experience | Effort |
|---|---|---|---|
| Direct DMG | Free | Gatekeeper warning | Low |
| Notarized DMG | $99/yr | Seamless install | Medium |
| Homebrew Cask | $99/yr* | `brew install` | Medium |
| GitHub Releases | Free/$99 | Standard for utilities | Low |
| **Mac App Store** | **N/A** | **Not possible** | **N/A** |

\* Notarization recommended for Homebrew acceptance

The most common path for utilities like this: **Notarized DMG on GitHub Releases + Homebrew Cask**.
