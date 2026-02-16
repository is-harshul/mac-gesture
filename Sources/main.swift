import Cocoa
import Foundation
import Carbon.HIToolbox

#if !NO_SPARKLE
import Sparkle
#endif

// ============================================================================
// MARK: - MultitouchSupport Framework Bridge
// ============================================================================

typealias MTContactCallbackFunction = @convention(c) (
    UnsafeMutableRawPointer,   // device
    UnsafeMutableRawPointer,   // touch data array (raw)
    Int32,                     // numTouches
    Double,                    // timestamp
    Int32                      // frame
) -> Void

private let mtFrameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
private let mtFramework: UnsafeMutableRawPointer? = dlopen(mtFrameworkPath, RTLD_LAZY)

private let _MTDeviceCreateList: @convention(c) () -> CFArray = {
    guard let handle = mtFramework, let sym = dlsym(handle, "MTDeviceCreateList") else {
        fatalError("Cannot load MTDeviceCreateList")
    }
    return unsafeBitCast(sym, to: (@convention(c) () -> CFArray).self)
}()

private let _MTDeviceStart: @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32 = {
    guard let handle = mtFramework, let sym = dlsym(handle, "MTDeviceStart") else {
        fatalError("Cannot load MTDeviceStart")
    }
    return unsafeBitCast(sym, to: (@convention(c) (UnsafeMutableRawPointer, Int32) -> Int32).self)
}()

private let _MTDeviceStop: @convention(c) (UnsafeMutableRawPointer) -> Void = {
    guard let handle = mtFramework, let sym = dlsym(handle, "MTDeviceStop") else {
        fatalError("Cannot load MTDeviceStop")
    }
    return unsafeBitCast(sym, to: (@convention(c) (UnsafeMutableRawPointer) -> Void).self)
}()

private let _MTRegisterContactFrameCallback: @convention(c) (UnsafeMutableRawPointer, MTContactCallbackFunction) -> Void = {
    guard let handle = mtFramework, let sym = dlsym(handle, "MTRegisterContactFrameCallback") else {
        fatalError("Cannot load MTRegisterContactFrameCallback")
    }
    return unsafeBitCast(sym, to: (@convention(c) (UnsafeMutableRawPointer, MTContactCallbackFunction) -> Void).self)
}()

// ============================================================================
// MARK: - MTTouch Raw Memory Layout
// ============================================================================
// The MultitouchSupport private framework uses a C struct for each finger.
// We read fields at known byte offsets rather than casting to a Swift struct
// (which fails with @convention(c) due to tuple fields).
//
// Struct layout (standard macOS internal trackpad):
//   Offset  0: frame          (Int32)
//   Offset  4: (padding for Double alignment)
//   Offset  8: timestamp      (Double)
//   Offset 16: identifier     (Int32)
//   Offset 20: state          (Int32)    — 4=touching
//   Offset 24: fingerID       (Int32)
//   Offset 28: handID         (Int32)
//   Offset 32: normalized.x   (Float)    — 0.0 to 1.0
//   Offset 36: normalized.y   (Float)    — 0.0 to 1.0
//   ...remaining fields...
//   Total stride: ~80–96 bytes depending on macOS version
//
// We auto-detect the stride on first callback to be safe.

let kNormXOffset = 32
let kNormYOffset = 36

/// Auto-detected struct stride (set on first callback with ≥2 fingers)
var detectedStride: Int = 0

/// Attempt to detect the MTTouch struct size by examining raw memory.
/// With 2+ fingers, we look for the second finger's normalized X at
/// candidate strides and check if it looks like a valid 0–1 coordinate.
func detectStride(touchData: UnsafeMutableRawPointer, count: Int) -> Int {
    guard count >= 2 else { return 0 }

    // Common struct sizes seen across macOS versions
    let candidates = [64, 72, 80, 84, 88, 96, 104, 112, 128]

    for stride in candidates {
        let x = touchData.load(fromByteOffset: stride + kNormXOffset, as: Float.self)
        let y = touchData.load(fromByteOffset: stride + kNormYOffset, as: Float.self)
        // Valid normalized coords are 0.0–1.0
        if x >= 0.0 && x <= 1.0 && y >= 0.0 && y <= 1.0 && (x > 0.001 || y > 0.001) {
            return stride
        }
    }
    return 0  // Could not detect
}

/// Read the average (centroid) of all finger positions from raw touch data.
/// Returns nil if stride is unknown or positions look invalid.
func readAveragePosition(touchData: UnsafeMutableRawPointer, count: Int) -> (x: Float, y: Float)? {
    guard detectedStride > 0, count > 0 else { return nil }

    var sumX: Float = 0
    var sumY: Float = 0
    var valid = 0

    for i in 0..<count {
        let base = detectedStride * i
        let x = touchData.load(fromByteOffset: base + kNormXOffset, as: Float.self)
        let y = touchData.load(fromByteOffset: base + kNormYOffset, as: Float.self)
        if x >= 0.0 && x <= 1.0 && y >= 0.0 && y <= 1.0 {
            sumX += x
            sumY += y
            valid += 1
        }
    }

    guard valid > 0 else { return nil }
    return (sumX / Float(valid), sumY / Float(valid))
}

// ============================================================================
// MARK: - Action Definitions
// ============================================================================

enum TapAction: String, CaseIterable {
    case middleClick      = "middle_click"
    case rightClick       = "right_click"
    case closeTab         = "close_tab"
    case newTab           = "new_tab"
    case reopenTab        = "reopen_tab"
    case refreshPage      = "refresh_page"
    case copySelection    = "copy"
    case pasteClipboard   = "paste"
    case undo             = "undo"
    case missionControl   = "mission_control"
    case launchpad        = "launchpad"
    case spotlight        = "spotlight"

    var displayName: String {
        switch self {
        case .middleClick:    return "Middle Click"
        case .rightClick:     return "Right Click"
        case .closeTab:       return "Close Tab  (⌘W)"
        case .newTab:         return "New Tab  (⌘T)"
        case .reopenTab:      return "Reopen Closed Tab  (⇧⌘T)"
        case .refreshPage:    return "Refresh Page  (⌘R)"
        case .copySelection:  return "Copy  (⌘C)"
        case .pasteClipboard: return "Paste  (⌘V)"
        case .undo:           return "Undo  (⌘Z)"
        case .missionControl: return "Mission Control"
        case .launchpad:      return "Launchpad"
        case .spotlight:      return "Spotlight  (⌘Space)"
        }
    }

    var category: String {
        switch self {
        case .middleClick, .rightClick: return "Mouse"
        case .closeTab, .newTab, .reopenTab, .refreshPage: return "Browser"
        case .copySelection, .pasteClipboard, .undo: return "Edit"
        case .missionControl, .launchpad, .spotlight: return "System"
        }
    }

    func execute() {
        switch self {
        case .middleClick:      simulateMiddleClick()
        case .rightClick:       simulateRightClick()
        case .closeTab:         simulateKeyCombo(key: kVK_ANSI_W, flags: .maskCommand)
        case .newTab:           simulateKeyCombo(key: kVK_ANSI_T, flags: .maskCommand)
        case .reopenTab:        simulateKeyCombo(key: kVK_ANSI_T, flags: [.maskCommand, .maskShift])
        case .refreshPage:      simulateKeyCombo(key: kVK_ANSI_R, flags: .maskCommand)
        case .copySelection:    simulateKeyCombo(key: kVK_ANSI_C, flags: .maskCommand)
        case .pasteClipboard:   simulateKeyCombo(key: kVK_ANSI_V, flags: .maskCommand)
        case .undo:             simulateKeyCombo(key: kVK_ANSI_Z, flags: .maskCommand)
        case .missionControl:   simulateKeyCombo(key: kVK_UpArrow, flags: .maskControl)
        case .launchpad:        openLaunchpad()
        case .spotlight:        simulateKeyCombo(key: kVK_Space, flags: .maskCommand)
        }
    }
}

// ============================================================================
// MARK: - Action Execution Helpers
// ============================================================================

func simulateMiddleClick() {
    guard let sourceEvent = CGEvent(source: nil) else { return }
    let cgPoint = sourceEvent.location

    guard let down = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                              mouseCursorPosition: cgPoint, mouseButton: .center),
          let up = CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp,
                            mouseCursorPosition: cgPoint, mouseButton: .center) else { return }
    down.setIntegerValueField(.mouseEventButtonNumber, value: 2)
    up.setIntegerValueField(.mouseEventButtonNumber, value: 2)
    down.post(tap: .cghidEventTap)
    usleep(15_000)
    up.post(tap: .cghidEventTap)
    if debugMode { print("🖱️ Middle-click at (\(Int(cgPoint.x)), \(Int(cgPoint.y)))") }
}

func simulateRightClick() {
    guard let sourceEvent = CGEvent(source: nil) else { return }
    let cgPoint = sourceEvent.location

    guard let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown,
                              mouseCursorPosition: cgPoint, mouseButton: .right),
          let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp,
                            mouseCursorPosition: cgPoint, mouseButton: .right) else { return }
    down.post(tap: .cghidEventTap)
    usleep(15_000)
    up.post(tap: .cghidEventTap)
    if debugMode { print("🖱️ Right-click at (\(Int(cgPoint.x)), \(Int(cgPoint.y)))") }
}

func simulateKeyCombo(key: Int, flags: CGEventFlags) {
    guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: false) else { return }
    keyDown.flags = flags
    keyUp.flags = flags
    keyDown.post(tap: .cghidEventTap)
    usleep(15_000)
    keyUp.post(tap: .cghidEventTap)
    if debugMode { print("⌨️ Key combo: \(currentAction.displayName)") }
}

func openLaunchpad() {
    if let kd = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(160), keyDown: true),
       let ku = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(160), keyDown: false) {
        kd.post(tap: .cghidEventTap); usleep(15_000); ku.post(tap: .cghidEventTap)
    } else {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Launchpad.app"))
    }
}

// ============================================================================
// MARK: - Global State
// ============================================================================

var isEnabled = true
var debugMode = false

/// Maximum tap duration — fingers must lift within this window.
/// Default 120ms: real taps are 30–100ms; swipes/pinches are 200ms+
var tapThreshold: TimeInterval = 0.12

/// Minimum duration to filter phantom touches
let minTapDuration: TimeInterval = 0.02

/// Maximum allowed finger movement (normalized 0–1 trackpad coords).
/// Anything above this means the fingers moved too much → swipe/pinch.
/// Trackpad is ~10cm wide, so 0.03 ≈ 3mm of movement allowed.
var maxMovement: Float = 0.03

var currentAction: TapAction = .middleClick

// Gesture tracking state
var touchStartTime: TimeInterval = 0
var isTrackingTouch = false
var maxFingersInGesture: Int32 = 0
var startCentroid: (x: Float, y: Float)? = nil
var maxDeviation: Float = 0.0
var registeredDevices: [UnsafeMutableRawPointer] = []

// Preferences
let defaults = UserDefaults.standard
let kAction = "selectedAction"
let kSensitivity = "tapThreshold"
let kEnabled = "isEnabled"
let kMaxMovement = "maxMovement"

func loadPreferences() {
    if let s = defaults.string(forKey: kAction), let a = TapAction(rawValue: s) { currentAction = a }
    if defaults.object(forKey: kSensitivity) != nil { tapThreshold = defaults.double(forKey: kSensitivity) }
    if defaults.object(forKey: kEnabled) != nil { isEnabled = defaults.bool(forKey: kEnabled) }
    if defaults.object(forKey: kMaxMovement) != nil { maxMovement = Float(defaults.double(forKey: kMaxMovement)) }
}

func savePreferences() {
    defaults.set(currentAction.rawValue, forKey: kAction)
    defaults.set(tapThreshold, forKey: kSensitivity)
    defaults.set(isEnabled, forKey: kEnabled)
    defaults.set(Double(maxMovement), forKey: kMaxMovement)
}

// ============================================================================
// MARK: - Multitouch Callback
// ============================================================================

let touchCallback: MTContactCallbackFunction = { _, touchData, numTouches, timestamp, frame in
    guard isEnabled else { return }

    let fingerCount = numTouches

    // --- Auto-detect struct stride on first multi-finger frame ---
    if detectedStride == 0 && fingerCount >= 2 {
        let stride = detectStride(touchData: touchData, count: Int(fingerCount))
        if stride > 0 {
            detectedStride = stride
            if debugMode { print("🔧 Detected MTTouch stride: \(stride) bytes") }
        }
    }

    // Track peak finger count
    if fingerCount > 0 {
        maxFingersInGesture = max(maxFingersInGesture, fingerCount)
    }

    // --- Exactly 4 fingers touched → start tracking ---
    if fingerCount == 4 && !isTrackingTouch {
        isTrackingTouch = true
        touchStartTime = timestamp
        maxFingersInGesture = 4
        maxDeviation = 0.0

        // Record starting centroid for movement rejection
        startCentroid = readAveragePosition(touchData: touchData, count: Int(fingerCount))

        if debugMode {
            let pos = startCentroid.map { "(\(String(format: "%.3f", $0.x)), \(String(format: "%.3f", $0.y)))" } ?? "n/a"
            print("👆 4-finger touch started at \(pos)")
        }
    }

    // --- While 4 fingers are down, track movement ---
    if fingerCount == 4 && isTrackingTouch {
        if let start = startCentroid,
           let current = readAveragePosition(touchData: touchData, count: Int(fingerCount)) {
            let dx = current.x - start.x
            let dy = current.y - start.y
            let dist = sqrtf(dx * dx + dy * dy)
            maxDeviation = max(maxDeviation, dist)
        }
    }

    // --- Fingers dropped below 4 → evaluate ---
    if fingerCount < 4 && isTrackingTouch {
        isTrackingTouch = false
        let duration = timestamp - touchStartTime

        let validDuration = duration > minTapDuration && duration < tapThreshold
        let validFingers = maxFingersInGesture == 4
        let validMovement = maxDeviation < maxMovement

        if debugMode {
            let ms = String(format: "%.0f", duration * 1000)
            let mv = String(format: "%.4f", maxDeviation)
            let reasons = [
                validDuration  ? nil : "duration(\(ms)ms)",
                validFingers   ? nil : "fingers(\(maxFingersInGesture))",
                validMovement  ? nil : "movement(\(mv))"
            ].compactMap { $0 }

            if validDuration && validFingers && validMovement {
                print("✅ TAP! \(ms)ms, moved \(mv) → \(currentAction.displayName)")
            } else {
                print("❌ Rejected: \(ms)ms, moved \(mv), max fingers \(maxFingersInGesture) — \(reasons.joined(separator: ", "))")
            }
        }

        if validDuration && validFingers && validMovement {
            DispatchQueue.main.async { currentAction.execute() }
        }

        // Reset
        maxFingersInGesture = 0
        maxDeviation = 0.0
        startCentroid = nil
    }

    // All fingers lifted → full reset
    if fingerCount == 0 {
        isTrackingTouch = false
        maxFingersInGesture = 0
        maxDeviation = 0.0
        startCentroid = nil
    }
}

// ============================================================================
// MARK: - Device Management
// ============================================================================

func startMultitouchMonitoring() {
    let cfList = _MTDeviceCreateList()
    let count = CFArrayGetCount(cfList)
    if count == 0 { print("❌ No multitouch devices found"); return }

    registeredDevices.removeAll()
    for i in 0..<count {
        guard let rawPtr = CFArrayGetValueAtIndex(cfList, i) else { continue }
        let device = UnsafeMutableRawPointer(mutating: rawPtr)
        _MTRegisterContactFrameCallback(device, touchCallback)
        if _MTDeviceStart(device, 0) == 0 {
            registeredDevices.append(device)
            print("✅ Device \(i): started")
        }
    }
    print("📱 Monitoring \(registeredDevices.count)/\(count) device(s)")
}

func restartMonitoring() {
    for d in registeredDevices { _MTDeviceStop(d) }
    registeredDevices.removeAll()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { startMultitouchMonitoring() }
}

// ============================================================================
// MARK: - Menu Bar Icon
// ============================================================================

func createMenuBarIcon(enabled: Bool) -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
        let ctx = NSGraphicsContext.current!.cgContext
        let color: NSColor = enabled ? .labelColor : .tertiaryLabelColor
        ctx.setFillColor(color.cgColor)

        // 4 finger dots
        let dotR: CGFloat = 2.0
        let y: CGFloat = 11.5
        let startX: CGFloat = 2.0
        let spacing: CGFloat = 3.7
        for i in 0..<4 {
            ctx.fillEllipse(in: CGRect(x: startX + CGFloat(i) * spacing, y: y,
                                        width: dotR * 2, height: dotR * 2))
        }

        // Trackpad outline
        let padRect = CGRect(x: 1.5, y: 1.0, width: 15, height: 9)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.2)
        let path = CGPath(roundedRect: padRect, cornerWidth: 2, cornerHeight: 2, transform: nil)
        ctx.addPath(path)
        ctx.strokePath()

        return true
    }
    image.isTemplate = true
    return image
}

// ============================================================================
// MARK: - AppDelegate
// ============================================================================

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var enabledMenuItem: NSMenuItem!
    var debugMenuItem: NSMenuItem!
    var actionMenuItems: [NSMenuItem] = []
    var sensitivityMenu: NSMenu!
    var movementMenu: NSMenu!
    var currentActionLabel: NSMenuItem!

    #if !NO_SPARKLE
    var updaterController: SPUStandardUpdaterController!
    #endif

    func applicationDidFinishLaunching(_ note: Notification) {
        print("========================================")
        print("  MacGesture v2.2")
        print("========================================")

        loadPreferences()

        #if !NO_SPARKLE
        // Initialize Sparkle auto-updater.
        // startingUpdater: true  → starts automatic background update checks
        // updaterDelegate: nil   → use default behavior
        // userDriverDelegate: nil
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        print("🔄 Sparkle auto-updater initialized")
        #endif

        checkAccessibility()
        setupStatusBar()
        startMultitouchMonitoring()

        print("")
        print("🚀 Running!")
        print("   Action:       \(currentAction.displayName)")
        print("   Tap window:   \(Int(tapThreshold * 1000))ms")
        print("   Max movement: \(String(format: "%.2f", maxMovement))")
        print("========================================")
    }

    func checkAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        print(trusted ? "✅ Accessibility: GRANTED" : "⚠️  Accessibility: NOT YET GRANTED")

        if !trusted {
            let a = NSAlert()
            a.messageText = "Accessibility Permission Required"
            a.informativeText = "MacGesture needs Accessibility permission to simulate clicks and keystrokes.\n\nGrant it in:\nSystem Settings → Privacy & Security → Accessibility"
            a.alertStyle = .warning
            a.addButton(withTitle: "Open System Settings")
            a.addButton(withTitle: "Continue")
            if a.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    // MARK: - Status Bar

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()
        rebuildMenu()
    }

    func updateIcon() {
        statusItem.button?.image = createMenuBarIcon(enabled: isEnabled)
        statusItem.button?.toolTip = isEnabled
            ? "MacGesture — \(currentAction.displayName)"
            : "MacGesture — Disabled"
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Header
        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: "MacGesture",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        menu.addItem(header)

        // Current action sublabel
        currentActionLabel = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        currentActionLabel.isEnabled = false
        updateActionLabel()
        menu.addItem(currentActionLabel)

        menu.addItem(.separator())

        // Enable toggle
        enabledMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
        enabledMenuItem.target = self
        enabledMenuItem.state = isEnabled ? .on : .off
        menu.addItem(enabledMenuItem)

        menu.addItem(.separator())

        // ── ACTION PICKER ──
        addSectionHeader(menu, "TAP ACTION")

        actionMenuItems.removeAll()
        for category in ["Mouse", "Browser", "Edit", "System"] {
            let actions = TapAction.allCases.filter { $0.category == category }
            if actions.isEmpty { continue }

            addCategoryLabel(menu, category)

            for action in actions {
                let item = NSMenuItem(title: action.displayName, action: #selector(selectAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action.rawValue
                item.state = (action == currentAction) ? .on : .off
                item.indentationLevel = 2
                actionMenuItems.append(item)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // ── TAP DURATION ──
        let sensItem = NSMenuItem(title: "Tap Duration (max)", action: nil, keyEquivalent: "")
        sensitivityMenu = NSMenu()
        let durations: [(String, TimeInterval)] = [
            ("80ms  (very fast tap only)", 0.08),
            ("100ms  (fast tap)", 0.10),
            ("120ms  (default)", 0.12),
            ("150ms  (comfortable)", 0.15),
            ("200ms  (relaxed)", 0.20),
            ("250ms  (generous)", 0.25),
            ("350ms  (very generous)", 0.35),
        ]
        for (label, val) in durations {
            let mi = NSMenuItem(title: label, action: #selector(setSens(_:)), keyEquivalent: "")
            mi.target = self; mi.representedObject = val
            mi.state = (abs(val - tapThreshold) < 0.001) ? .on : .off
            sensitivityMenu.addItem(mi)
        }
        sensItem.submenu = sensitivityMenu
        menu.addItem(sensItem)

        // ── MOVEMENT TOLERANCE ──
        let movItem = NSMenuItem(title: "Movement Tolerance", action: nil, keyEquivalent: "")
        movementMenu = NSMenu()
        let tolerances: [(String, Float)] = [
            ("Strict  (1.5mm — tap must be very still)", 0.015),
            ("Default  (3mm — small finger jitter OK)", 0.03),
            ("Loose  (5mm — more forgiving)", 0.05),
            ("Very Loose  (8mm — quite forgiving)", 0.08),
            ("Disabled  (no movement check)", 1.0),
        ]
        for (label, val) in tolerances {
            let mi = NSMenuItem(title: label, action: #selector(setMovement(_:)), keyEquivalent: "")
            mi.target = self; mi.representedObject = val
            mi.state = (abs(val - maxMovement) < 0.001) ? .on : .off
            movementMenu.addItem(mi)
        }
        movItem.submenu = movementMenu
        menu.addItem(movItem)

        menu.addItem(.separator())

        // Test & debug
        let test = NSMenuItem(title: "Test Action (2s delay)", action: #selector(testAction), keyEquivalent: "t")
        test.target = self
        menu.addItem(test)

        let restart = NSMenuItem(title: "Restart Touch Detection", action: #selector(doRestart), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)

        debugMenuItem = NSMenuItem(title: "Debug Logging", action: #selector(toggleDebug), keyEquivalent: "")
        debugMenuItem.target = self
        debugMenuItem.state = debugMode ? .on : .off
        menu.addItem(debugMenuItem)

        menu.addItem(.separator())

        // ── UPDATES & INFO ──
        #if !NO_SPARKLE
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "u")
        updateItem.target = self
        menu.addItem(updateItem)
        #endif

        // Version
        let versionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        let versionStr = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.2"
        versionItem.attributedTitle = NSAttributedString(
            string: "Version \(versionStr)",
            attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.tertiaryLabelColor]
        )
        menu.addItem(versionItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit MacGesture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func addSectionHeader(_ menu: NSMenu, _ text: String) {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor
        ])
        menu.addItem(item)
    }

    func addCategoryLabel(_ menu: NSMenu, _ text: String) {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: "  \(text)", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        menu.addItem(item)
    }

    func updateActionLabel() {
        currentActionLabel.attributedTitle = NSAttributedString(
            string: "  ▸ \(currentAction.displayName)",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
    }

    // MARK: - Actions

    @objc func toggleEnabled() {
        isEnabled.toggle()
        enabledMenuItem.state = isEnabled ? .on : .off
        updateIcon()
        savePreferences()
    }

    @objc func toggleDebug() {
        debugMode.toggle()
        debugMenuItem.state = debugMode ? .on : .off
        if debugMode { print("🔍 Debug ON — tap the trackpad to see events") }
    }

    @objc func selectAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = TapAction(rawValue: raw) else { return }
        currentAction = action
        for item in actionMenuItems {
            item.state = (item.representedObject as? String == raw) ? .on : .off
        }
        updateActionLabel()
        updateIcon()
        savePreferences()
        print("🔧 Action → \(action.displayName)")
    }

    @objc func setSens(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? TimeInterval else { return }
        tapThreshold = v
        sensitivityMenu.items.forEach { $0.state = (abs(($0.representedObject as? TimeInterval ?? -1) - v) < 0.001) ? .on : .off }
        savePreferences()
        print("⏱️ Tap duration → \(Int(v * 1000))ms")
    }

    @objc func setMovement(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Float else { return }
        maxMovement = v
        movementMenu.items.forEach { $0.state = (abs(($0.representedObject as? Float ?? -1) - v) < 0.001) ? .on : .off }
        savePreferences()
        print("📏 Movement tolerance → \(String(format: "%.1f", v * 100))mm")
    }

    @objc func testAction() {
        print("🧪 Testing '\(currentAction.displayName)' in 2s...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            currentAction.execute()
            print("🧪 Done!")
        }
    }

    @objc func doRestart() { restartMonitoring() }

    #if !NO_SPARKLE
    @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
    #endif
}

// ============================================================================
// MARK: - Entry Point
// ============================================================================

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
