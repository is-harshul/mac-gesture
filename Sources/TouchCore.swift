// Portions adapted from Kinara (https://github.com/0x1p0/kinara), MIT License, Copyright (c) 2026 0x1p0.
import Foundation

struct TouchContact: Equatable {
    let id: Int32
    let x: Double
    let y: Double
    var major: Double = 0   // sensor ellipse, millimetres; 0 = not reported
    var minor: Double = 0
}

enum MTLayout {
    static let stride = 96
    static let pathIndex = 16   // Int32
    static let state = 20       // Int32
    static let normX = 32       // Float
    static let normY = 36       // Float
    static let majorAxis = 60   // Float
    static let minorAxis = 64   // Float
    static let maxContacts = 16
}

/// nil means the frame is malformed and the caller must cancel the gesture.
func parseContacts(_ data: UnsafeRawPointer?, count: Int) -> [TouchContact]? {
    if count < 0 || count > MTLayout.maxContacts { return nil }
    if count == 0 { return [] }
    guard let data = data else { return nil }

    var contacts: [TouchContact] = []
    for i in 0..<count {
        let base = i * MTLayout.stride
        let state = data.load(fromByteOffset: base + MTLayout.state, as: Int32.self)
        if state < 0 || state > 7 { return nil }
        if state != 3 && state != 4 { continue }

        let id = data.load(fromByteOffset: base + MTLayout.pathIndex, as: Int32.self)
        let x = Double(data.load(fromByteOffset: base + MTLayout.normX, as: Float.self))
        let y = Double(data.load(fromByteOffset: base + MTLayout.normY, as: Float.self))
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { return nil }

        let major = Double(data.load(fromByteOffset: base + MTLayout.majorAxis, as: Float.self))
        let minor = Double(data.load(fromByteOffset: base + MTLayout.minorAxis, as: Float.self))
        let sizeOK = major.isFinite && minor.isFinite && major > 0 && minor > 0 && major < 200 && minor < 200
        contacts.append(TouchContact(id: id, x: x, y: y,
                                     major: sizeOK ? major : 0,
                                     minor: sizeOK ? minor : 0))
    }
    return contacts
}

struct PalmFilter {
    static let palmWidth = 10.0    // mm, narrow axis
    static let palmLength = 17.0   // mm, long axis, only while nearly still
    static let stillStep = 0.012   // normalized movement per frame

    struct Result {
        var fingers: [TouchContact] = []
        var withdrewFinger = false  // a contact already passed as a finger became a palm
        var newPalms = 0            // contacts first judged palms in this frame
        var palmSize = 0.0          // largest axis among newPalms, mm
    }

    private var palms: Set<Int32> = []
    private var fingers: [Int32: TouchContact] = [:]

    static func isPalm(_ contact: TouchContact, still: Bool = true) -> Bool {
        let major = max(contact.major, contact.minor)
        let minor = min(contact.major, contact.minor)
        guard major.isFinite, minor.isFinite, minor > 0 else { return false }
        return minor >= palmWidth || (still && major >= palmLength)
    }

    mutating func filter(_ contacts: [TouchContact]) -> Result {
        var result = Result()
        var nextPalms: Set<Int32> = []
        var nextFingers: [Int32: TouchContact] = [:]

        for contact in contacts {
            if palms.contains(contact.id) {
                nextPalms.insert(contact.id)
                continue
            }
            let previous = fingers[contact.id]
            var still = true
            if let p = previous {
                still = hypot(contact.x - p.x, contact.y - p.y) <= PalmFilter.stillStep
            }
            if PalmFilter.isPalm(contact, still: still) {
                nextPalms.insert(contact.id)
                result.newPalms += 1
                result.palmSize = max(result.palmSize, max(contact.major, contact.minor))
                if previous != nil { result.withdrewFinger = true }
            } else {
                nextFingers[contact.id] = contact
                result.fingers.append(contact)
            }
        }
        palms = nextPalms
        fingers = nextFingers
        return result
    }
}

// MARK: - Multi-finger tap recognizer

struct TapConfig: Equatable {
    var maxDuration = 0.12
    var minDuration = 0.02
    var maxTravel = 0.03
    var typingCooldown = 0.45       // 0 disables the cooldown
    var enabledCounts: Set<Int> = [3]
}

enum RejectReason: String { case duration, movement, notConfigured, typing, unstable }

enum TapVerdict: Equatable {
    case tap(fingers: Int)
    case rejected(fingers: Int, reason: RejectReason, duration: Double, travel: Double)
}

struct MultiFingerTapRecognizer {
    private enum Phase { case idle, tracking, blocked }

    private var phase = Phase.idle
    private var lastKeyDown: Double?
    private var startTime = 0.0
    private var peak = 0
    private var trackedIDs = Set<Int32>()
    private var origins: [Int32: (x: Double, y: Double)] = [:]
    private var travel = 0.0
    private var unstable = false
    private var typedDuringTouch = false
    private var startedInCooldown = false

    mutating func keyDown(at timestamp: Double) {
        lastKeyDown = timestamp
        if phase == .tracking { typedDuringTouch = true }
    }

    /// Abandon the touch in progress; nothing is recognized until every finger lifts.
    mutating func cancel() {
        phase = .blocked
    }

    mutating func process(contacts: [TouchContact], timestamp: Double, config: TapConfig) -> TapVerdict? {
        let count = contacts.count
        switch phase {
        case .blocked:
            if count == 0 { phase = .idle }
            return nil
        case .idle:
            guard count >= 3 else { return nil }
            phase = .tracking
            startedInCooldown = lastKeyDown.map { timestamp - $0 < config.typingCooldown } ?? false
            typedDuringTouch = false
            unstable = false
            beginSegment(contacts, timestamp: timestamp)
            return nil
        case .tracking:
            break
        }

        if count > peak {
            beginSegment(contacts, timestamp: timestamp)
            return nil
        }
        for contact in contacts {
            if let o = origins[contact.id] {
                travel = max(travel, hypot(contact.x - o.x, contact.y - o.y))
            }
        }
        if count == peak {
            if Set(contacts.map { $0.id }) != trackedIDs { unstable = true }
            return nil
        }

        let duration = timestamp - startTime
        let typing = config.typingCooldown > 0 && (startedInCooldown || typedDuringTouch)
        let verdict: TapVerdict
        if let reason = rejection(typing: typing, duration: duration, config: config) {
            verdict = .rejected(fingers: peak, reason: reason, duration: duration, travel: travel)
        } else {
            verdict = .tap(fingers: peak)
        }
        phase = count == 0 ? .idle : .blocked
        return verdict
    }

    private mutating func beginSegment(_ contacts: [TouchContact], timestamp: Double) {
        startTime = timestamp
        peak = contacts.count
        travel = 0
        trackedIDs = Set(contacts.map { $0.id })
        origins = [:]
        for contact in contacts { origins[contact.id] = (contact.x, contact.y) }
    }

    private func rejection(typing: Bool, duration: Double, config: TapConfig) -> RejectReason? {
        if typing { return .typing }
        if unstable { return .unstable }
        if !config.enabledCounts.contains(peak) { return .notConfigured }
        if !(duration > config.minDuration && duration < config.maxDuration) { return .duration }
        if travel >= config.maxTravel { return .movement }
        return nil
    }
}

// MARK: - Touch pipeline

struct TouchPipeline {
    static let maximumFrameAge = 0.12   // seconds

    struct Output {
        var verdict: TapVerdict?
        var palmsIgnored = 0     // palms first seen in this frame
        var palmSize = 0.0       // mm, largest of them
        var cancelled: String?   // "stale", "malformed" or "palm" when this frame cancelled the gesture
    }

    var palmRejection = true
    private var recognizer = MultiFingerTapRecognizer()
    private var palmFilter = PalmFilter()

    mutating func keyDown(at timestamp: Double) { recognizer.keyDown(at: timestamp) }
    mutating func cancel() { recognizer.cancel() }

    /// contacts == nil means parseContacts reported a malformed frame.
    mutating func handle(contacts: [TouchContact]?, timestamp: Double, now: Double, config: TapConfig) -> Output {
        var output = Output()
        guard let contacts = contacts else {
            recognizer.cancel()
            output.cancelled = "malformed"
            return output
        }
        if now - timestamp > TouchPipeline.maximumFrameAge {
            recognizer.cancel()
            output.cancelled = "stale"
            if contacts.isEmpty {
                // A late lift still unblocks the recognizer and clears the palm filter.
                _ = palmFilter.filter(contacts)
                _ = recognizer.process(contacts: contacts, timestamp: timestamp, config: config)
            }
            return output
        }
        var passed = contacts
        if palmRejection {
            let result = palmFilter.filter(contacts)
            output.palmsIgnored = result.newPalms
            output.palmSize = result.palmSize
            if result.withdrewFinger {
                recognizer.cancel()
                output.cancelled = "palm"
                return output
            }
            passed = result.fingers
        }
        output.verdict = recognizer.process(contacts: passed, timestamp: timestamp, config: config)
        return output
    }
}

/// Limits haptic pulses to one per `minimumInterval`. The caller supplies the clock.
struct HapticGate {
    static let minimumInterval = 0.05
    private var lastPulse: Double?

    mutating func allow(at time: Double) -> Bool {
        guard time.isFinite else { return false }
        if let last = lastPulse, time - last < HapticGate.minimumInterval { return false }
        lastPulse = time
        return true
    }
}
