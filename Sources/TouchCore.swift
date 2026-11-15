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
