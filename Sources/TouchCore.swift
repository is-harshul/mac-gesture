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
