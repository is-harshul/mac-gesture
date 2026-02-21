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
    case customShortcut   = "custom_shortcut"

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
        case .customShortcut: return "Custom Shortcut"
        }
    }

    var category: String {
        switch self {
        case .none: return "Off"
        case .middleClick, .rightClick: return "Mouse"
        case .closeTab, .newTab, .reopenTab, .refreshPage: return "Browser"
        case .copySelection, .pasteClipboard, .undo: return "Edit"
        case .missionControl, .launchpad, .spotlight: return "System"
        case .customShortcut: return "Custom"
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
        case .missionControl:   openMissionControl()
        case .launchpad:        openLaunchpad()
        case .spotlight:        simulateKeyCombo(key: kVK_Space, flags: .maskCommand)
        case .customShortcut:   break // handled separately with finger count context
        }
    }
}

// ── Custom Shortcut Storage ──

struct CustomShortcut {
    var keyCode: Int
    var modifiers: UInt64 // CGEventFlags.rawValue

    var isEmpty: Bool { return keyCode == -1 }

    func execute() {
        guard !isEmpty else { return }
        simulateKeyCombo(key: keyCode, flags: CGEventFlags(rawValue: modifiers))
    }

    var displayString: String {
        guard !isEmpty else { return "Not set" }
        return formatShortcut(keyCode: keyCode, modifiers: CGEventFlags(rawValue: modifiers))
    }
}

var customShortcut3 = CustomShortcut(keyCode: -1, modifiers: 0)
var customShortcut4 = CustomShortcut(keyCode: -1, modifiers: 0)
var customShortcut5 = CustomShortcut(keyCode: -1, modifiers: 0)

func customShortcutFor(fingerCount: Int) -> CustomShortcut {
    switch fingerCount {
    case 3: return customShortcut3
    case 4: return customShortcut4
    case 5: return customShortcut5
    default: return CustomShortcut(keyCode: -1, modifiers: 0)
    }
}

func executeGestureAction(action: TapAction, fingerCount: Int) {
    if action == .customShortcut {
        customShortcutFor(fingerCount: fingerCount).execute()
    } else {
        action.execute()
    }
}

func formatShortcut(keyCode: Int, modifiers: CGEventFlags) -> String {
    var parts: [String] = []
    if modifiers.contains(.maskControl)   { parts.append("⌃") }
    if modifiers.contains(.maskAlternate) { parts.append("⌥") }
    if modifiers.contains(.maskShift)     { parts.append("⇧") }
    if modifiers.contains(.maskCommand)   { parts.append("⌘") }

    let keyNames: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_ForwardDelete: "⌦",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "PgUp", kVK_PageDown: "PgDn",
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
    ]

    parts.append(keyNames[keyCode] ?? "Key\(keyCode)")
    return parts.joined()
}

let selectableActions = TapAction.allCases.filter { $0 != .none && $0 != .customShortcut }

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

func openMissionControl() {
    // Key code 160 = Mission Control (F3/Exposé key), same approach as Launchpad.
    // Falls back to launching Mission Control.app if the key event doesn't work.
    if let kd = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(160), keyDown: true),
       let ku = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(160), keyDown: false) {
        kd.post(tap: .cghidEventTap); usleep(15_000); ku.post(tap: .cghidEventTap)
    } else {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
    }
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

var gesture3 = GestureConfig(fingerCount: 3, action: .middleClick)
var gesture4 = GestureConfig(fingerCount: 4, action: .none)
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

    // Load custom shortcuts
    for fc in [3, 4, 5] {
        let keyVal = defaults.object(forKey: "custom_key_\(fc)finger") as? Int ?? -1
        let modVal = defaults.object(forKey: "custom_mod_\(fc)finger") as? UInt64 ?? 0
        let cs = CustomShortcut(keyCode: keyVal, modifiers: modVal)
        switch fc {
        case 3: customShortcut3 = cs
        case 4: customShortcut4 = cs
        case 5: customShortcut5 = cs
        default: break
        }
    }

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

    // Save custom shortcuts
    for fc in [3, 4, 5] {
        let cs = customShortcutFor(fingerCount: fc)
        defaults.set(cs.keyCode, forKey: "custom_key_\(fc)finger")
        defaults.set(cs.modifiers, forKey: "custom_mod_\(fc)finger")
    }
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
            let fingers = peakFingers
            DispatchQueue.main.async { executeGestureAction(action: execAction, fingerCount: fingers) }
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
// MARK: - Accessibility Helper
// ============================================================================

/// Check accessibility WITHOUT prompting (for UI status display)
func isAccessibilityGranted() -> Bool {
    return AXIsProcessTrusted()
}

/// Check accessibility WITH prompt (for first launch)
func checkAccessibilityWithPrompt() -> Bool {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    return AXIsProcessTrustedWithOptions(opts)
}

func openAccessibilitySettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
}

// ============================================================================
// MARK: - External Links
// ============================================================================

private let kBuyMeACoffeeURL = "https://www.buymeacoffee.com/is.harshul"

// ============================================================================
// MARK: - Popover Content ViewController
// ============================================================================

class GesturePopoverVC: NSViewController {
    let W: CGFloat = 300
    let padH: CGFloat = 12 // horizontal padding (left & right)
    let padVTop: CGFloat = 8 // padding above header
    let padVBottom: CGFloat = 12 // padding below footer
    var tabControl: NSSegmentedControl!
    var actionContainer: NSView!
    var actionButtons: [NSButton] = []
    var selectedTab = 0  // 0=3F, 1=4F, 2=5F — default to 3F (primary default gesture)
    var shortcutRecorderBtn: NSButton?
    var keyMonitor: Any?
    var isRecording = false

    weak var appDelegate: AppDelegate?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: W, height: 100))
        view.wantsLayer = true
        rebuildUI()
    }

    func rebuildUI() {
        view.subviews.forEach { $0.removeFromSuperview() }
        actionButtons.removeAll()

        // Reset view frame to prevent stale geometry from previous popover showing
        view.frame = NSRect(x: 0, y: 0, width: W, height: 100)

        let innerW = W - padH * 2
        var y: CGFloat = padVBottom

        // ── BUY ME A COFFEE ──
        let coffeeBtn = makeLink("☕ Buy me a coffee", action: #selector(openBuyMeACoffee))
        coffeeBtn.target = self
        coffeeBtn.frame.origin = CGPoint(x: padH, y: y)
        view.addSubview(coffeeBtn)
        y += 26

        // ── QUIT + VERSION ──
        let quitBtn = makeLink("Quit MacGesture", action: #selector(appDelegate?.doQuit), color: NSColor.systemRed.withAlphaComponent(0.6))
        quitBtn.target = appDelegate
        quitBtn.frame.origin = CGPoint(x: padH, y: y)
        view.addSubview(quitBtn)

        let versionStr = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.1"
        let vLabel = NSTextField(labelWithString: "v\(versionStr)")
        vLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        vLabel.textColor = .tertiaryLabelColor
        vLabel.sizeToFit()
        vLabel.frame.origin = CGPoint(x: W - padH - vLabel.frame.width, y: y + 1)
        view.addSubview(vLabel)
        y += 30

        sep(&y)

        // ── TOOLS ──
        let debugBtn = makeCheckbox("Debug Logging", checked: debugMode, action: #selector(appDelegate?.toggleDebug))
        debugBtn.target = appDelegate
        debugBtn.frame.origin = CGPoint(x: padH, y: y)
        view.addSubview(debugBtn)
        y += 26

        let restartBtn = makeLink("Restart Touch Detection", action: #selector(appDelegate?.doRestart))
        restartBtn.target = appDelegate
        restartBtn.frame.origin = CGPoint(x: padH, y: y)
        view.addSubview(restartBtn)
        y += 26

        let testBtn = makeLink("Test Current Tab Action (2s)", action: #selector(doTest))
        testBtn.target = self
        testBtn.frame.origin = CGPoint(x: padH, y: y)
        view.addSubview(testBtn)
        y += 30

        sep(&y)

        // ── GENERAL SETTINGS ──
        sectionHeader("GENERAL", at: &y)

        // Movement tolerance
        label("Movement Tolerance", at: &y)
        let movPopup = NSPopUpButton(frame: NSRect(x: padH, y: y, width: innerW, height: 24), pullsDown: false)
        movPopup.font = .systemFont(ofSize: 11); movPopup.controlSize = .small
        let tolerances: [(String, Float)] = [
            ("Strict (1.5mm)", 0.015), ("Default (3mm)", 0.03),
            ("Loose (5mm)", 0.05), ("Very Loose (8mm)", 0.08), ("Disabled", 1.0)
        ]
        for (i, (lbl, val)) in tolerances.enumerated() {
            movPopup.addItem(withTitle: lbl)
            movPopup.item(at: i)?.representedObject = val
            if abs(val - maxMovement) < 0.001 { movPopup.selectItem(at: i) }
        }
        movPopup.target = appDelegate; movPopup.action = #selector(appDelegate?.movementChanged(_:))
        view.addSubview(movPopup)
        y += 30

        // Tap duration
        label("Tap Duration (max)", at: &y)
        let durPopup = NSPopUpButton(frame: NSRect(x: padH, y: y, width: innerW, height: 24), pullsDown: false)
        durPopup.font = .systemFont(ofSize: 11); durPopup.controlSize = .small
        let durations: [(String, TimeInterval)] = [
            ("80ms (very fast)", 0.08), ("100ms (fast)", 0.10),
            ("120ms (default)", 0.12), ("150ms (comfortable)", 0.15),
            ("200ms (relaxed)", 0.20), ("250ms (generous)", 0.25),
            ("350ms (very generous)", 0.35)
        ]
        for (i, (lbl, val)) in durations.enumerated() {
            durPopup.addItem(withTitle: lbl)
            durPopup.item(at: i)?.representedObject = val
            if abs(val - tapThreshold) < 0.001 { durPopup.selectItem(at: i) }
        }
        durPopup.target = appDelegate; durPopup.action = #selector(appDelegate?.durationChanged(_:))
        view.addSubview(durPopup)
        y += 32

        sep(&y)

        // ── ACTION LIST (for selected tab) ──
        actionContainer = NSView(frame: NSRect(x: 0, y: y, width: W, height: 0))
        view.addSubview(actionContainer)
        buildActionList()
        y += actionContainer.frame.height

        sep(&y)

        // ── TAB CONTROL ──
        tabControl = NSSegmentedControl(labels: ["3F", "4F", "5F"], trackingMode: .selectOne,
                                         target: self, action: #selector(tabChanged))
        tabControl.selectedSegment = selectedTab
        tabControl.segmentStyle = .texturedRounded
        tabControl.frame = NSRect(x: padH, y: y, width: innerW, height: 26)
        let segmentWidth = innerW / 3
        for i in 0..<3 { tabControl.setWidth(segmentWidth, forSegment: i) }
        view.addSubview(tabControl)
        updateTabAppearance()
        y += 36

        sep(&y)

        // ── ENABLED TOGGLE ──
        let enableBtn = makeCheckbox("Enabled", checked: isEnabled, action: #selector(appDelegate?.toggleEnabled))
        enableBtn.target = appDelegate
        enableBtn.font = .systemFont(ofSize: 12, weight: .medium)
        enableBtn.frame.origin = CGPoint(x: padH, y: y)
        view.addSubview(enableBtn)
        y += 30

        sep(&y)

        // ── ACCESSIBILITY STATUS ──
        let granted = isAccessibilityGranted()
        let accessBg = NSView(frame: NSRect(x: padH, y: y, width: innerW, height: 28))
        accessBg.wantsLayer = true
        accessBg.layer?.cornerRadius = 6
        let softGreen = NSColor.systemGreen.withAlphaComponent(0.55)
        let softAmber = NSColor.systemOrange.withAlphaComponent(0.55)
        accessBg.layer?.backgroundColor = granted
            ? NSColor.systemGreen.withAlphaComponent(0.07).cgColor
            : NSColor.systemOrange.withAlphaComponent(0.07).cgColor
        view.addSubview(accessBg)

        let dotColor: NSColor = granted ? softGreen : softAmber
        let dotLabel = NSTextField(labelWithString: "●")
        dotLabel.font = .systemFont(ofSize: 10)
        dotLabel.textColor = dotColor
        dotLabel.sizeToFit()
        dotLabel.frame.origin = CGPoint(x: padH + 8, y: y + 7)
        view.addSubview(dotLabel)

        let statusText = granted ? "Accessibility: Granted" : "Accessibility: Not Granted"
        let statusLabel = NSTextField(labelWithString: statusText)
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = granted ? softGreen : softAmber
        statusLabel.sizeToFit()
        statusLabel.frame.origin = CGPoint(x: padH + 22, y: y + 6)
        view.addSubview(statusLabel)

        if !granted {
            let grantBtn = makeLink("Grant →", action: #selector(openAccessSettings), color: softAmber)
            grantBtn.target = self
            grantBtn.font = .systemFont(ofSize: 11, weight: .medium)
            grantBtn.sizeToFit()
            grantBtn.frame.origin = CGPoint(x: W - padH - grantBtn.frame.width - 6, y: y + 5)
            view.addSubview(grantBtn)
        }
        y += 36

        // ── HEADER ──
        let header = NSTextField(labelWithString: "MacGesture")
        header.font = .boldSystemFont(ofSize: 15)
        header.textColor = .labelColor
        header.sizeToFit()
        header.frame.origin = CGPoint(x: padH, y: y - 6)
        view.addSubview(header)

        let summaryText = gesturesSummaryShort()
        let summary = NSTextField(labelWithString: summaryText)
        summary.font = .systemFont(ofSize: 9)
        summary.textColor = .tertiaryLabelColor
        summary.sizeToFit()
        summary.frame.origin = CGPoint(x: W - padH - summary.frame.width, y: y + 4)
        view.addSubview(summary)
        y += 28 + padVTop

        // Final — set both the view frame and preferredContentSize so the
        // popover sizes correctly on every open, not just the first time.
        let finalSize = NSSize(width: W, height: y)
        view.frame = NSRect(origin: .zero, size: finalSize)
        preferredContentSize = finalSize
    }

    func buildActionList() {
        actionContainer.subviews.forEach { $0.removeFromSuperview() }
        actionButtons.removeAll()
        stopRecording()

        let gesture = currentGesture()
        var y: CGFloat = 6

        // Disabled option
        let offBtn = makeRadio("Disabled (Off)", selected: gesture.action == .none, tag: -1)
        offBtn.frame.origin = CGPoint(x: padH + 4, y: y)
        actionContainer.addSubview(offBtn)
        actionButtons.append(offBtn)
        y += 22

        for category in ["Mouse", "Browser", "Edit", "System"] {
            let actions = selectableActions.filter { $0.category == category }
            if actions.isEmpty { continue }

            let catLabel = NSTextField(labelWithString: category.uppercased())
            catLabel.font = .systemFont(ofSize: 9, weight: .semibold)
            catLabel.textColor = .tertiaryLabelColor
            catLabel.sizeToFit()
            catLabel.frame.origin = CGPoint(x: padH + 4, y: y + 3)
            actionContainer.addSubview(catLabel)
            y += 18

            for act in actions {
                let tag = TapAction.allCases.firstIndex(of: act) ?? 0
                let btn = makeRadio(act.displayName, selected: act == gesture.action, tag: tag)
                btn.frame.origin = CGPoint(x: padH + 16, y: y)
                actionContainer.addSubview(btn)
                actionButtons.append(btn)
                y += 22
            }
            y += 4
        }

        // ── CUSTOM SHORTCUT ──
        let customCatLabel = NSTextField(labelWithString: "CUSTOM")
        customCatLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        customCatLabel.textColor = .tertiaryLabelColor
        customCatLabel.sizeToFit()
        customCatLabel.frame.origin = CGPoint(x: padH + 4, y: y + 3)
        actionContainer.addSubview(customCatLabel)
        y += 18

        let customTag = TapAction.allCases.firstIndex(of: .customShortcut) ?? 0
        let customBtn = makeRadio("Custom Keyboard Shortcut", selected: gesture.action == .customShortcut, tag: customTag)
        customBtn.frame.origin = CGPoint(x: padH + 16, y: y)
        actionContainer.addSubview(customBtn)
        actionButtons.append(customBtn)
        y += 24

        // Shortcut recorder button
        let cs = customShortcutFor(fingerCount: gesture.fingerCount)
        let recorderTitle = cs.isEmpty ? "Click to record shortcut..." : cs.displayString
        let recorder = NSButton(title: recorderTitle, target: self, action: #selector(startRecordingShortcut))
        recorder.bezelStyle = .recessed
        recorder.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        recorder.frame = NSRect(x: padH + 28, y: y, width: W - padH * 2 - 28, height: 30)
        recorder.isEnabled = (gesture.action == .customShortcut)
        recorder.alphaValue = (gesture.action == .customShortcut) ? 1.0 : 0.4
        actionContainer.addSubview(recorder)
        shortcutRecorderBtn = recorder
        y += 30

        y += 6
        actionContainer.frame.size.height = y
    }

    func currentGesture() -> GestureConfig {
        switch selectedTab {
        case 0: return gesture3
        case 2: return gesture5
        default: return gesture4
        }
    }

    func updateTabAppearance() {
        let gestures = [gesture3, gesture4, gesture5]
        for (i, g) in gestures.enumerated() {
            let label = "\(g.fingerCount)F" + (g.action.isEnabled ? " ●" : "")
            tabControl.setLabel(label, forSegment: i)
        }
    }

    func gesturesSummaryShort() -> String {
        var parts: [String] = []
        if gesture3.action.isEnabled { parts.append("3F") }
        if gesture4.action.isEnabled { parts.append("4F") }
        if gesture5.action.isEnabled { parts.append("5F") }
        return parts.isEmpty ? "none active" : parts.joined(separator: " · ") + " active"
    }

    // MARK: - Actions

    @objc func tabChanged() {
        selectedTab = tabControl.selectedSegment
        // Only rebuild action list and tab labels — avoids full UI rebuild and layout shift
        buildActionList()
        updateTabAppearance()
    }

    @objc func actionSelected(_ sender: NSButton) {
        let tag = sender.tag
        let action: TapAction
        if tag == -1 {
            action = .none
        } else {
            let allCases = TapAction.allCases
            guard tag >= 0 && tag < allCases.count else { return }
            action = allCases[tag]
        }

        switch selectedTab {
        case 0: gesture3.action = action
        case 2: gesture5.action = action
        default: gesture4.action = action
        }

        savePreferences()
        appDelegate?.updateIcon()
        print("🔧 \(currentGesture().fingerCount)-finger → \(action.displayName)")

        let gesture = currentGesture()
        for btn in actionButtons {
            if btn.tag == -1 {
                btn.state = gesture.action == .none ? .on : .off
            } else {
                let allCases = TapAction.allCases
                if btn.tag < allCases.count {
                    btn.state = allCases[btn.tag] == gesture.action ? .on : .off
                }
            }
        }

        // Enable/disable shortcut recorder based on selection
        let isCustom = (action == .customShortcut)
        shortcutRecorderBtn?.isEnabled = isCustom
        shortcutRecorderBtn?.alphaValue = isCustom ? 1.0 : 0.4
        if !isCustom { stopRecording() }

        updateTabAppearance()
    }

    @objc func startRecordingShortcut() {
        guard !isRecording else { return }
        isRecording = true
        shortcutRecorderBtn?.title = "Press a key combo..."
        shortcutRecorderBtn?.contentTintColor = .systemOrange

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            let keyCode = Int(event.keyCode)
            // Convert NSEvent modifier flags to CGEventFlags
            var cgFlags: UInt64 = 0
            if event.modifierFlags.contains(.command)  { cgFlags |= CGEventFlags.maskCommand.rawValue }
            if event.modifierFlags.contains(.shift)    { cgFlags |= CGEventFlags.maskShift.rawValue }
            if event.modifierFlags.contains(.option)   { cgFlags |= CGEventFlags.maskAlternate.rawValue }
            if event.modifierFlags.contains(.control)  { cgFlags |= CGEventFlags.maskControl.rawValue }

            let cs = CustomShortcut(keyCode: keyCode, modifiers: cgFlags)
            let fingerCount = self.currentGesture().fingerCount
            switch fingerCount {
            case 3: customShortcut3 = cs
            case 4: customShortcut4 = cs
            case 5: customShortcut5 = cs
            default: break
            }
            savePreferences()

            self.shortcutRecorderBtn?.title = cs.displayString
            self.shortcutRecorderBtn?.contentTintColor = nil
            self.stopRecording()
            print("🔧 Custom shortcut for \(fingerCount)F → \(cs.displayString)")
            return nil // consume the event
        }
    }

    func stopRecording() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        isRecording = false
    }

    @objc func doTest() {
        let gesture = currentGesture()
        let action = gesture.action
        guard action.isEnabled else {
            print("🧪 No action configured for \(gesture.fingerCount)-finger tap")
            return
        }
        let fingerCount = gesture.fingerCount
        let displayName = action == .customShortcut
            ? customShortcutFor(fingerCount: fingerCount).displayString
            : action.displayName
        print("🧪 Testing '\(displayName)' in 2s...")
        appDelegate?.popover.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            executeGestureAction(action: action, fingerCount: fingerCount)
            print("🧪 Done!")
        }
    }

    @objc func openAccessSettings() {
        openAccessibilitySettings()
    }

    @objc func openBuyMeACoffee() {
        guard let url = URL(string: kBuyMeACoffeeURL) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - UI Helpers

    func makeRadio(_ title: String, selected: Bool, tag: Int) -> NSButton {
        let btn = NSButton(radioButtonWithTitle: title, target: self, action: #selector(actionSelected(_:)))
        btn.font = .systemFont(ofSize: 11)
        btn.state = selected ? .on : .off
        btn.tag = tag
        btn.sizeToFit()
        return btn
    }

    func makeCheckbox(_ title: String, checked: Bool, action: Selector) -> NSButton {
        let btn = NSButton(checkboxWithTitle: title, target: nil, action: action)
        btn.font = .systemFont(ofSize: 12)
        btn.state = checked ? .on : .off
        btn.sizeToFit()
        return btn
    }

    func makeLink(_ title: String, action: Selector, color: NSColor = .systemBlue) -> NSButton {
        let btn = NSButton(title: title, target: nil, action: action)
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 11)
        btn.contentTintColor = color
        btn.sizeToFit()
        return btn
    }

    func sep(_ y: inout CGFloat) {
        let s = NSBox(frame: NSRect(x: padH, y: y, width: W - padH * 2, height: 1))
        s.boxType = .separator
        view.addSubview(s)
        y += 12
    }

    func sectionHeader(_ text: String, at y: inout CGFloat) {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .tertiaryLabelColor
        l.sizeToFit()
        l.frame.origin = CGPoint(x: padH, y: y)
        view.addSubview(l)
        y += 20
    }

    func label(_ text: String, at y: inout CGFloat) {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.sizeToFit()
        l.frame.origin = CGPoint(x: padH, y: y)
        view.addSubview(l)
        y += 18
    }
}

// ============================================================================
// MARK: - AppDelegate
// ============================================================================

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover = NSPopover()
    var popoverVC: GesturePopoverVC!
    var accessibilityTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        print("========================================")
        print("  MacGesture v3.1")
        print("========================================")

        loadPreferences()

        // Check accessibility (with prompt on first launch)
        let granted = checkAccessibilityWithPrompt()
        print(granted ? "✅ Accessibility: GRANTED" : "⚠️  Accessibility: NOT YET GRANTED")
        if !granted {
            let a = NSAlert()
            a.messageText = "Accessibility Permission Required"
            a.informativeText = "MacGesture needs Accessibility permission to detect trackpad gestures and simulate actions.\n\nAfter every rebuild, you may need to toggle the permission OFF and ON again in System Settings.\n\nSystem Settings → Privacy & Security → Accessibility"
            a.alertStyle = .warning
            a.addButton(withTitle: "Open System Settings")
            a.addButton(withTitle: "Continue")
            if a.runModal() == .alertFirstButtonReturn {
                openAccessibilitySettings()
            }
        }

        setupStatusBar()
        startMultitouchMonitoring()

        // Periodic accessibility re-check (every 5s) — auto-restart monitoring when granted
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            let nowGranted = isAccessibilityGranted()
            if nowGranted && registeredDevices.isEmpty {
                print("✅ Accessibility just granted — starting touch monitoring")
                startMultitouchMonitoring()
            }
        }

        print("")
        print("🚀 Running!")
        for (g, fc) in [(gesture3, 3), (gesture4, 4), (gesture5, 5)] {
            let name = g.action == .customShortcut
                ? "\(g.action.displayName) (\(customShortcutFor(fingerCount: fc).displayString))"
                : g.action.displayName
            print("   \(fc)-finger: \(name)")
        }
        print("   Tap window:   \(Int(tapThreshold * 1000))ms")
        print("   Max movement: \(String(format: "%.2f", maxMovement))")
        print("========================================")
    }

    // MARK: - Status Bar

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()

        popoverVC = GesturePopoverVC()
        popoverVC.appDelegate = self
        popover.contentViewController = popoverVC
        popover.behavior = .transient
        popover.animates = true

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    func updateIcon() {
        statusItem.button?.image = createMenuBarIcon(enabled: isEnabled)
        if isEnabled {
            var active: [String] = []
            for (g, fc) in [(gesture3, 3), (gesture4, 4), (gesture5, 5)] {
                guard g.action.isEnabled else { continue }
                let name = g.action == .customShortcut
                    ? customShortcutFor(fingerCount: fc).displayString
                    : g.action.displayName
                active.append("\(fc)F→\(name)")
            }
            statusItem.button?.toolTip = active.isEmpty
                ? "MacGesture — No gestures configured"
                : "MacGesture — \(active.joined(separator: ", "))"
        } else {
            statusItem.button?.toolTip = "MacGesture — Disabled"
        }
    }

    // MARK: - Popover

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Rebuild UI first, then assign a fresh VC so the popover
            // picks up the new preferredContentSize cleanly every time.
            popoverVC = GesturePopoverVC()
            popoverVC.appDelegate = self
            popover.contentViewController = popoverVC
            popover.contentSize = popoverVC.preferredContentSize
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    // MARK: - Actions from Popover

    @objc func toggleEnabled(_ sender: NSButton) {
        isEnabled = (sender.state == .on)
        updateIcon()
        savePreferences()
    }

    @objc func toggleDebug(_ sender: NSButton) {
        debugMode = (sender.state == .on)
        if debugMode { print("🔍 Debug ON — tap the trackpad to see events") }
    }

    @objc func durationChanged(_ sender: NSPopUpButton) {
        guard let val = sender.selectedItem?.representedObject as? TimeInterval else { return }
        tapThreshold = val
        savePreferences()
        print("⏱️ Tap duration → \(Int(val * 1000))ms")
    }

    @objc func movementChanged(_ sender: NSPopUpButton) {
        guard let val = sender.selectedItem?.representedObject as? Float else { return }
        maxMovement = val
        savePreferences()
        print("📏 Movement tolerance → \(String(format: "%.1f", val * 100))mm")
    }

    @objc func doRestart() {
        popover.performClose(nil)
        restartMonitoring()
    }

    @objc func doQuit() {
        NSApplication.shared.terminate(nil)
    }
}

// ============================================================================
// MARK: - Entry Point
// ============================================================================

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
