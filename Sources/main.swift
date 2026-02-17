import Cocoa
import Foundation
import Carbon.HIToolbox

// ============================================================================
// MARK: - MultitouchSupport Framework Bridge
// ============================================================================

typealias MTContactCallbackFunction = @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeMutableRawPointer,
    Int32,
    Double,
    Int32
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

let kNormXOffset = 32
let kNormYOffset = 36
var detectedStride: Int = 0

func detectStride(touchData: UnsafeMutableRawPointer, count: Int) -> Int {
    guard count >= 2 else { return 0 }
    let candidates = [64, 72, 80, 84, 88, 96, 104, 112, 128]
    for stride in candidates {
        let x = touchData.load(fromByteOffset: stride + kNormXOffset, as: Float.self)
        let y = touchData.load(fromByteOffset: stride + kNormYOffset, as: Float.self)
        if x >= 0.0 && x <= 1.0 && y >= 0.0 && y <= 1.0 && (x > 0.001 || y > 0.001) {
            return stride
        }
    }
    return 0
}

func readAveragePosition(touchData: UnsafeMutableRawPointer, count: Int) -> (x: Float, y: Float)? {
    guard detectedStride > 0, count > 0 else { return nil }
    var sumX: Float = 0, sumY: Float = 0, valid = 0
    for i in 0..<count {
        let base = detectedStride * i
        let x = touchData.load(fromByteOffset: base + kNormXOffset, as: Float.self)
        let y = touchData.load(fromByteOffset: base + kNormYOffset, as: Float.self)
        if x >= 0.0 && x <= 1.0 && y >= 0.0 && y <= 1.0 {
            sumX += x; sumY += y; valid += 1
        }
    }
    guard valid > 0 else { return nil }
    return (sumX / Float(valid), sumY / Float(valid))
}

// ============================================================================
// MARK: - Action Definitions
// ============================================================================

enum TapAction: String, CaseIterable {
    case none             = "none"
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
        case .none:           return "Disabled"
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
        case .none: return "Off"
        case .middleClick, .rightClick: return "Mouse"
        case .closeTab, .newTab, .reopenTab, .refreshPage: return "Browser"
        case .copySelection, .pasteClipboard, .undo: return "Edit"
        case .missionControl, .launchpad, .spotlight: return "System"
        }
    }

    var isEnabled: Bool { return self != .none }

    func execute() {
        guard self != .none else { return }
        switch self {
        case .none:             break
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

let selectableActions = TapAction.allCases.filter { $0 != .none }

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
    if debugMode { print("⌨️ Key combo executed") }
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
// MARK: - Gesture Configuration
// ============================================================================

struct GestureConfig {
    let fingerCount: Int
    var action: TapAction
    var label: String { return "\(fingerCount)-Finger Tap" }
    var prefKey: String { return "action_\(fingerCount)finger" }
}

var gesture3 = GestureConfig(fingerCount: 3, action: .none)
var gesture4 = GestureConfig(fingerCount: 4, action: .middleClick)
var gesture5 = GestureConfig(fingerCount: 5, action: .none)

func gestureConfig(for fingerCount: Int) -> GestureConfig? {
    switch fingerCount {
    case 3: return gesture3
    case 4: return gesture4
    case 5: return gesture5
    default: return nil
    }
}

// ============================================================================
// MARK: - Global State
// ============================================================================

var isEnabled = true
var debugMode = false
var tapThreshold: TimeInterval = 0.12
let minTapDuration: TimeInterval = 0.02
var maxMovement: Float = 0.03

var touchStartTime: TimeInterval = 0
var isTrackingTouch = false
var maxFingersInGesture: Int32 = 0
var startCentroid: (x: Float, y: Float)? = nil
var maxDeviation: Float = 0.0
var registeredDevices: [UnsafeMutableRawPointer] = []

let defaults = UserDefaults.standard
let kSensitivity = "tapThreshold"
let kEnabled = "isEnabled"
let kMaxMovement = "maxMovement"

func loadPreferences() {
    if let s = defaults.string(forKey: gesture3.prefKey), let a = TapAction(rawValue: s) { gesture3.action = a }
    if let s = defaults.string(forKey: gesture4.prefKey), let a = TapAction(rawValue: s) { gesture4.action = a }
    if let s = defaults.string(forKey: gesture5.prefKey), let a = TapAction(rawValue: s) { gesture5.action = a }
    if defaults.object(forKey: kSensitivity) != nil { tapThreshold = defaults.double(forKey: kSensitivity) }
    if defaults.object(forKey: kEnabled) != nil { isEnabled = defaults.bool(forKey: kEnabled) }
    if defaults.object(forKey: kMaxMovement) != nil { maxMovement = Float(defaults.double(forKey: kMaxMovement)) }

    // Migrate old single-action preference
    if let old = defaults.string(forKey: "selectedAction"), let a = TapAction(rawValue: old) {
        gesture4.action = a
        defaults.removeObject(forKey: "selectedAction")
        savePreferences()
    }
}

func savePreferences() {
    defaults.set(gesture3.action.rawValue, forKey: gesture3.prefKey)
    defaults.set(gesture4.action.rawValue, forKey: gesture4.prefKey)
    defaults.set(gesture5.action.rawValue, forKey: gesture5.prefKey)
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

    // Auto-detect struct stride
    if detectedStride == 0 && fingerCount >= 2 {
        let stride = detectStride(touchData: touchData, count: Int(fingerCount))
        if stride > 0 {
            detectedStride = stride
            if debugMode { print("🔧 Detected MTTouch stride: \(stride) bytes") }
        }
    }

    // 3+ fingers land → start tracking
    if fingerCount >= 3 && !isTrackingTouch {
        isTrackingTouch = true
        touchStartTime = timestamp
        maxFingersInGesture = fingerCount
        maxDeviation = 0.0
        startCentroid = readAveragePosition(touchData: touchData, count: Int(fingerCount))

        if debugMode {
            let pos = startCentroid.map { "(\(String(format: "%.3f", $0.x)), \(String(format: "%.3f", $0.y)))" } ?? "n/a"
            print("👆 \(fingerCount)-finger touch started at \(pos)")
        }
    }

    // While 3+ fingers are down → update peak count + track movement
    if fingerCount >= 3 && isTrackingTouch {
        // More fingers added → upgrade gesture (e.g. 3→4)
        if fingerCount > maxFingersInGesture {
            maxFingersInGesture = fingerCount
            touchStartTime = timestamp
            startCentroid = readAveragePosition(touchData: touchData, count: Int(fingerCount))
            maxDeviation = 0.0
            if debugMode { print("👆 Upgraded to \(fingerCount)-finger gesture") }
        }

        // Track movement ONLY at peak finger count.
        // When fingers start lifting (4→3), the centroid shifts because a
        // different set of fingers is down. We must stop tracking movement
        // at that point to avoid false swipe rejection.
        if fingerCount == maxFingersInGesture {
            if let start = startCentroid,
               let current = readAveragePosition(touchData: touchData, count: Int(fingerCount)) {
                let dx = current.x - start.x
                let dy = current.y - start.y
                let dist = sqrtf(dx * dx + dy * dy)
                maxDeviation = max(maxDeviation, dist)
            }
        }
    }

    // Finger count dropped below peak → evaluate gesture immediately.
    // Don't wait for all fingers to lift (fingerCount == 0), because the
    // time spent going 4→3→2→1→0 adds to duration and causes rejection.
    if isTrackingTouch && fingerCount < maxFingersInGesture {
        isTrackingTouch = false
        let duration = timestamp - touchStartTime
        let peakFingers = Int(maxFingersInGesture)

        let validDuration = duration > minTapDuration && duration < tapThreshold
        let validMovement = maxDeviation < maxMovement

        let config = gestureConfig(for: peakFingers)
        let action = config?.action ?? .none
        let validGesture = action.isEnabled

        if debugMode {
            let ms = String(format: "%.0f", duration * 1000)
            let mv = String(format: "%.4f", maxDeviation)
            let reasons = [
                validDuration  ? nil : "duration(\(ms)ms)",
                validMovement  ? nil : "movement(\(mv))",
                validGesture   ? nil : "\(peakFingers)F not configured"
            ].compactMap { $0 }

            if validDuration && validMovement && validGesture {
                print("✅ \(peakFingers)-FINGER TAP! \(ms)ms, moved \(mv) → \(action.displayName)")
            } else if peakFingers >= 3 && peakFingers <= 5 {
                print("❌ Rejected \(peakFingers)F: \(ms)ms, moved \(mv) — \(reasons.joined(separator: ", "))")
            }
        }

        if validDuration && validMovement && validGesture {
            let execAction = action
            DispatchQueue.main.async { execAction.execute() }
        }

        maxFingersInGesture = 0
        maxDeviation = 0.0
        startCentroid = nil
    }

    // All fingers lifted → full reset (catches edge cases)
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

        let dotR: CGFloat = 1.6
        let y: CGFloat = 12.0
        let dotCount = 4
        let totalWidth: CGFloat = 14.0
        let spacing = totalWidth / CGFloat(dotCount - 1)
        let startX: CGFloat = 2.0
        for i in 0..<dotCount {
            ctx.fillEllipse(in: CGRect(x: startX + CGFloat(i) * spacing - dotR,
                                        y: y, width: dotR * 2, height: dotR * 2))
        }

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
    var sensitivityMenu: NSMenu!
    var movementMenu: NSMenu!

    var gesture3MenuItems: [NSMenuItem] = []
    var gesture4MenuItems: [NSMenuItem] = []
    var gesture5MenuItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        print("========================================")
        print("  MacGesture v3.0.1")
        print("========================================")

        loadPreferences()
        checkAccessibility()
        setupStatusBar()
        startMultitouchMonitoring()

        print("")
        print("🚀 Running!")
        print("   3-finger: \(gesture3.action.displayName)")
        print("   4-finger: \(gesture4.action.displayName)")
        print("   5-finger: \(gesture5.action.displayName)")
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
        if isEnabled {
            var active: [String] = []
            if gesture3.action.isEnabled { active.append("3F→\(gesture3.action.displayName)") }
            if gesture4.action.isEnabled { active.append("4F→\(gesture4.action.displayName)") }
            if gesture5.action.isEnabled { active.append("5F→\(gesture5.action.displayName)") }
            statusItem.button?.toolTip = active.isEmpty
                ? "MacGesture — No gestures configured"
                : "MacGesture — \(active.joined(separator: ", "))"
        } else {
            statusItem.button?.toolTip = "MacGesture — Disabled"
        }
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

        // Summary
        let summary = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        summary.isEnabled = false
        summary.attributedTitle = NSAttributedString(
            string: gesturesSummary(),
            attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(summary)

        menu.addItem(.separator())

        enabledMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
        enabledMenuItem.target = self
        enabledMenuItem.state = isEnabled ? .on : .off
        menu.addItem(enabledMenuItem)

        menu.addItem(.separator())

        // ── GESTURE SECTIONS ──
        gesture3MenuItems = buildGestureSection(menu: menu, gesture: gesture3,
                                                 action: #selector(select3Finger(_:)))
        menu.addItem(.separator())

        gesture4MenuItems = buildGestureSection(menu: menu, gesture: gesture4,
                                                 action: #selector(select4Finger(_:)))
        menu.addItem(.separator())

        gesture5MenuItems = buildGestureSection(menu: menu, gesture: gesture5,
                                                 action: #selector(select5Finger(_:)))
        menu.addItem(.separator())

        // ── SETTINGS ──
        let sensItem = NSMenuItem(title: "Tap Duration (max)", action: nil, keyEquivalent: "")
        sensitivityMenu = NSMenu()
        let durations: [(String, TimeInterval)] = [
            ("80ms  (very fast only)", 0.08),
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

        let movItem = NSMenuItem(title: "Movement Tolerance", action: nil, keyEquivalent: "")
        movementMenu = NSMenu()
        let tolerances: [(String, Float)] = [
            ("Strict  (1.5mm — very still)", 0.015),
            ("Default  (3mm — jitter OK)", 0.03),
            ("Loose  (5mm — forgiving)", 0.05),
            ("Very Loose  (8mm)", 0.08),
            ("Disabled", 1.0),
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
        let test = NSMenuItem(title: "Test 4-Finger Action (2s)", action: #selector(testAction), keyEquivalent: "t")
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

        let versionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        let versionStr = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0.1"
        versionItem.attributedTitle = NSAttributedString(
            string: "Version \(versionStr)",
            attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.tertiaryLabelColor]
        )
        menu.addItem(versionItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MacGesture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: - Gesture Section Builder

    func buildGestureSection(menu: NSMenu, gesture: GestureConfig, action: Selector) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        // Section header with current state
        let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        let currentLabel = gesture.action.isEnabled ? gesture.action.displayName : "Off"
        let headerText = NSMutableAttributedString()
        headerText.append(NSAttributedString(string: "\(gesture.fingerCount)-FINGER TAP", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]))
        headerText.append(NSAttributedString(string: "  \(currentLabel)", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: gesture.action.isEnabled ? NSColor.systemBlue : NSColor.tertiaryLabelColor
        ]))
        headerItem.attributedTitle = headerText
        menu.addItem(headerItem)

        // Disabled option
        let disabledItem = NSMenuItem(title: "Disabled (Off)", action: action, keyEquivalent: "")
        disabledItem.target = self
        disabledItem.representedObject = TapAction.none.rawValue
        disabledItem.state = (gesture.action == .none) ? .on : .off
        disabledItem.indentationLevel = 1
        menu.addItem(disabledItem)
        items.append(disabledItem)

        // Actions by category
        for category in ["Mouse", "Browser", "Edit", "System"] {
            let actions = selectableActions.filter { $0.category == category }
            if actions.isEmpty { continue }

            let catItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            catItem.isEnabled = false
            catItem.attributedTitle = NSAttributedString(string: "  \(category)", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
            menu.addItem(catItem)

            for act in actions {
                let item = NSMenuItem(title: act.displayName, action: action, keyEquivalent: "")
                item.target = self
                item.representedObject = act.rawValue
                item.state = (act == gesture.action) ? .on : .off
                item.indentationLevel = 2
                menu.addItem(item)
                items.append(item)
            }
        }

        return items
    }

    func gesturesSummary() -> String {
        var parts: [String] = []
        if gesture3.action.isEnabled { parts.append("  3F → \(gesture3.action.displayName)") }
        if gesture4.action.isEnabled { parts.append("  4F → \(gesture4.action.displayName)") }
        if gesture5.action.isEnabled { parts.append("  5F → \(gesture5.action.displayName)") }
        return parts.isEmpty ? "  No gestures configured" : parts.joined(separator: "\n")
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

    @objc func select3Finger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = TapAction(rawValue: raw) else { return }
        gesture3.action = action
        finishGestureUpdate("3-finger", action)
    }

    @objc func select4Finger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = TapAction(rawValue: raw) else { return }
        gesture4.action = action
        finishGestureUpdate("4-finger", action)
    }

    @objc func select5Finger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = TapAction(rawValue: raw) else { return }
        gesture5.action = action
        finishGestureUpdate("5-finger", action)
    }

    func finishGestureUpdate(_ label: String, _ action: TapAction) {
        updateIcon()
        savePreferences()
        rebuildMenu()
        print("🔧 \(label) → \(action.displayName)")
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
        let action = gesture4.action
        print("🧪 Testing '\(action.displayName)' in 2s...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            action.execute()
            print("🧪 Done!")
        }
    }

    @objc func doRestart() { restartMonitoring() }
}

// ============================================================================
// MARK: - Entry Point
// ============================================================================

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
