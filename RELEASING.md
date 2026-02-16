# Releasing with Sparkle Auto-Updates

This guide walks through setting up and publishing auto-updates for MacGesture using the [Sparkle](https://sparkle-project.org/) framework.

## Overview

When a user runs MacGesture, Sparkle periodically fetches an **appcast XML** file from a URL you control. If a newer version is listed in the appcast, Sparkle shows an update prompt, downloads the new version, and replaces the app — all automatically.

```
User's Mac                          Your Server (GitHub Pages / Releases)
┌──────────────┐                    ┌──────────────────────┐
│ MacGesture│ ── checks ──────►  │ appcast.xml          │
│  + Sparkle   │                    │  └─ v2.3 → .zip URL  │
│              │ ◄── download ───── │ MacGesture-2.3.zip│
│              │                    └──────────────────────┘
│  installs &  │
│  relaunches  │
└──────────────┘
```

## One-Time Setup

### 1. Generate EdDSA Signing Keys

Sparkle uses EdDSA (Ed25519) signatures to verify that updates are authentic and haven't been tampered with.

```bash
# Build the project first (downloads Sparkle tools)
./build.sh

# Generate a keypair — stored in your macOS Keychain
./vendor/Sparkle/bin/generate_keys
```

This prints something like:

```
A]  key has been generated. Add the public key to your app's Info.plist:

    <key>SUPublicEDKey</key>
    <string>2Bx7Gqn7FSGi+4y1S8ByXLPYxV0sd3hSCwEv9d2pOqc=</string>
```

**Copy the public key** and paste it into `Info.plist` as the value for `SUPublicEDKey`.

> **Important:** The private key lives in your macOS Keychain. Back it up! If you lose it, you can never sign updates that existing installations will accept. Run `./vendor/Sparkle/bin/generate_keys -x` to export the private key for backup.

### 2. Choose an Appcast Host

The appcast XML needs to be served over HTTPS. Common options:

| Host | URL Pattern | Setup |
|---|---|---|
| **GitHub Pages** | `https://you.github.io/MacGesture/appcast.xml` | Enable Pages on the repo, serve from a `gh-pages` branch or `/docs` folder |
| **GitHub Releases** (raw) | Direct download URL for appcast.xml in a release | Simple but harder to update |
| **Any web server** | Your choice | Upload appcast.xml to any HTTPS-accessible location |

**Recommended: GitHub Pages.** It's free, HTTPS by default, and easy to update.

### 3. Update Info.plist

Set these values before your first release:

```xml
<!-- Your appcast URL -->
<key>SUFeedURL</key>
<string>https://is-harshul.github.io/mac-gesture/appcast.xml</string>

<!-- Your EdDSA public key (from step 1) -->
<key>SUPublicEDKey</key>
<string>YOUR_ACTUAL_PUBLIC_KEY_HERE</string>
```

### 4. Set Up GitHub Pages (if using)

```bash
# Create a gh-pages branch with just the appcast
git checkout --orphan gh-pages
git rm -rf .
echo "MacGesture updates" > index.html
git add index.html
git commit -m "Initialize GitHub Pages"
git push origin gh-pages
git checkout main
```

Then enable Pages in the repo settings: **Settings → Pages → Source → Deploy from branch → gh-pages**.

---

## Publishing a Release

### Step 1: Bump the Version

Edit `Info.plist` — update both version strings:

```xml
<key>CFBundleVersion</key>
<string>2.3</string>
<key>CFBundleShortVersionString</key>
<string>2.3</string>
```

### Step 2: Build

```bash
./build.sh
```

### Step 3: Create the Release

```bash
chmod +x release.sh
./release.sh 2.3
```

This will:
1. Create `releases/MacGesture-2.3.zip` (the update archive)
2. Sign it with your EdDSA private key (from Keychain)
3. Generate/update `releases/appcast.xml` with the new version entry

### Step 4: Edit Release Notes

Open `releases/appcast.xml` and write human-readable release notes in the `<description>` block:

```xml
<description><![CDATA[
    <h2>MacGesture 2.3</h2>
    <ul>
        <li>Added new "Screenshot" action</li>
        <li>Improved tap detection on M3 MacBook Pro</li>
        <li>Fixed menu bar icon on external displays</li>
    </ul>
]]></description>
```

### Step 5: Upload the Archive

```bash
# Using GitHub CLI
gh release create v2.3 releases/MacGesture-2.3.zip \
    --title "MacGesture 2.3" \
    --notes "Added new actions, improved tap detection."
```

Or upload manually via the GitHub web UI: **Releases → Draft a new release → Attach the .zip file**.

### Step 6: Publish the Appcast

```bash
# Switch to gh-pages and update the appcast
git checkout gh-pages
cp releases/appcast.xml appcast.xml
git add appcast.xml
git commit -m "Update appcast for v2.3"
git push origin gh-pages
git checkout main
```

### Step 7: Verify

```bash
# Check the appcast is accessible
curl -s https://is-harshul.github.io/mac-gesture/appcast.xml | head -20

# Check the download URL works
curl -I https://github.com/is-harshul/mac-gesture/releases/download/v2.3/MacGesture-2.3.zip
```

---

## Alternative: Use Sparkle's generate_appcast Tool

If you prefer an automated approach, Sparkle includes a `generate_appcast` tool that scans a directory of archives and creates the appcast XML automatically:

```bash
# Put all release zips in the releases/ folder
./vendor/Sparkle/bin/generate_appcast releases/
```

This reads the EdDSA key from your Keychain, inspects each archive, and generates a complete `appcast.xml`. It's less flexible for custom release notes but requires zero manual XML editing.

---

## How the Update Flow Works

1. **Background check:** Every 24 hours (configurable via `SUScheduledCheckInterval` in Info.plist), Sparkle fetches `appcast.xml` from your `SUFeedURL`.

2. **Version comparison:** Sparkle compares `sparkle:version` in the appcast against `CFBundleVersion` in the running app's Info.plist.

3. **User prompt:** If a newer version exists, Sparkle shows a native update dialog with your release notes, a "Install Update" button, and a "Skip This Version" option.

4. **Download & verify:** Sparkle downloads the `.zip`, verifies the EdDSA signature matches your `SUPublicEDKey`, extracts the new `.app`, and replaces the old one.

5. **Relaunch:** Sparkle relaunches the app with the new version.

Users can also trigger this manually via **"Check for Updates…"** in the menu bar.

---

## Troubleshooting

### "Check for Updates" does nothing

- Verify `SUFeedURL` in Info.plist points to an accessible HTTPS URL
- Check Console.app for Sparkle-related log messages
- Ensure the appcast XML is valid (no XML syntax errors)

### Update found but signature verification fails

- The archive must be signed with the private key matching the `SUPublicEDKey` in the **currently running** app's Info.plist
- If you regenerated keys, existing users on older versions won't be able to verify new updates signed with the new key
- Never lose your private key! Back it up with `generate_keys -x`

### Update downloads but fails to install

- The `.zip` must contain `MacGesture.app` at the top level (not nested in a folder)
- The `release.sh` script uses `ditto` which handles this correctly

### Want to test updates locally

```bash
# Serve the appcast from a local web server
cd releases
python3 -m http.server 8080

# Temporarily change SUFeedURL in Info.plist to:
# http://localhost:8080/appcast.xml

# Build, install, and trigger "Check for Updates"
```

---

## Security Notes

- **EdDSA signatures** prevent man-in-the-middle attacks on the update download. Even if someone intercepts the download, they can't substitute a malicious binary without your private key.
- **HTTPS for the appcast** prevents attackers from injecting fake version info.
- **Never commit your private key** to the repository. It lives in your macOS Keychain only.
- If your signing key is compromised, you must release a manually-installed version with a new key, as automatic updates from the compromised key can no longer be trusted.
