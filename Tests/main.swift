import Foundation

// MARK: - Harness

var totalPassed = 0
var totalFailed = 0
var currentFailures = 0

func expect(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        currentFailures += 1
        print("  FAIL (line \(line)): \(message)")
    }
}

func test(_ name: String, _ body: () -> Void) {
    currentFailures = 0
    body()
    if currentFailures == 0 {
        totalPassed += 1
        print("PASS \(name)")
    } else {
        totalFailed += 1
        print("FAIL \(name)")
    }
}

func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }

// MARK: - Helpers

func makeFrame(_ records: [(id: Int32, state: Int32, x: Float, y: Float, major: Float, minor: Float)]) -> UnsafeMutableRawPointer {
    let bytes = max(records.count, 1) * MTLayout.stride
    let buf = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 16)
    buf.initializeMemory(as: UInt8.self, repeating: 0, count: bytes)
    for (i, r) in records.enumerated() {
        let base = i * MTLayout.stride
        buf.storeBytes(of: r.id, toByteOffset: base + MTLayout.pathIndex, as: Int32.self)
        buf.storeBytes(of: r.state, toByteOffset: base + MTLayout.state, as: Int32.self)
        buf.storeBytes(of: r.x, toByteOffset: base + MTLayout.normX, as: Float.self)
        buf.storeBytes(of: r.y, toByteOffset: base + MTLayout.normY, as: Float.self)
        buf.storeBytes(of: r.major, toByteOffset: base + MTLayout.majorAxis, as: Float.self)
        buf.storeBytes(of: r.minor, toByteOffset: base + MTLayout.minorAxis, as: Float.self)
    }
    return buf
}

// MARK: - Contact parsing tests

func testParseKeepsOnlyTouchingStates() {
    let f = makeFrame([
        (5, 4, 0.25, 0.75, 9, 7),
        (6, 3, 0.5, 0.5, 8, 6),
        (7, 7, 0.1, 0.1, 5, 5),
    ])
    defer { f.deallocate() }
    let c = parseContacts(f, count: 3)
    expect(c?.count == 2, "expected 2 contacts, got \(String(describing: c?.count))")
    expect(c?.map { $0.id } == [5, 6], "ids should be [5, 6]")
    if let first = c?.first {
        expect(near(first.x, 0.25), "x")
        expect(near(first.y, 0.75), "y")
        expect(near(first.major, 9), "major")
        expect(near(first.minor, 7), "minor")
    }
}

func testParseEmptyFrame() {
    let c = parseContacts(nil, count: 0)
    expect(c != nil && c!.isEmpty, "empty frame should parse to []")
}

func testParseRejectsNilPointerWithCount() {
    expect(parseContacts(nil, count: 2) == nil, "nil pointer with count > 0 should be nil")
}

func testParseRejectsTooManyContacts() {
    let f = makeFrame([(1, 4, 0.5, 0.5, 5, 5)])
    defer { f.deallocate() }
    expect(parseContacts(f, count: 17) == nil, "count 17 should be nil")
}

func testParseRejectsBadState() {
    let f = makeFrame([(1, 9, 0.5, 0.5, 5, 5)])
    defer { f.deallocate() }
    expect(parseContacts(f, count: 1) == nil, "state 9 should be nil")
}

func testParseRejectsOutOfRangePosition() {
    let a = makeFrame([(1, 4, 1.5, 0.5, 5, 5)])
    defer { a.deallocate() }
    expect(parseContacts(a, count: 1) == nil, "x 1.5 should be nil")
    let b = makeFrame([(1, 4, .nan, 0.5, 5, 5)])
    defer { b.deallocate() }
    expect(parseContacts(b, count: 1) == nil, "x NaN should be nil")
}

func testParseDropsImplausibleSize() {
    let f = makeFrame([(1, 4, 0.5, 0.5, 250, 7)])
    defer { f.deallocate() }
    let c = parseContacts(f, count: 1)
    expect(c?.count == 1, "one contact expected")
    expect(c?.first?.major == 0 && c?.first?.minor == 0, "size should be zeroed")
}

func testParseSkipsHoverWithBadPosition() {
    let f = makeFrame([
        (1, 1, .nan, 0.5, 5, 5),
        (2, 4, 0.5, 0.5, 5, 5),
    ])
    defer { f.deallocate() }
    let c = parseContacts(f, count: 2)
    expect(c?.count == 1, "hover record skipped, 1 contact expected")
}

// MARK: - Palm filter tests

func c(_ id: Int32, _ x: Double, _ y: Double, major: Double = 8, minor: Double = 7) -> TouchContact {
    TouchContact(id: id, x: x, y: y, major: major, minor: minor)
}

func testWideContactIsPalm() {
    var f = PalmFilter()
    let r = f.filter([c(1, 0.5, 0.5, major: 20, minor: 12)])
    expect(r.fingers.isEmpty, "wide contact is not a finger")
    expect(r.newPalms == 1, "one new palm")
    expect(near(r.palmSize, 20), "palmSize 20, got \(r.palmSize)")
}

func testLongStillContactIsPalm() {
    var f = PalmFilter()
    let r = f.filter([c(1, 0.5, 0.5, major: 18, minor: 7)])
    expect(r.fingers.isEmpty, "long still contact is a palm")
}

func testLongMovingContactStaysFinger() {
    var f = PalmFilter()
    _ = f.filter([c(1, 0.50, 0.5)])
    let r = f.filter([c(1, 0.55, 0.5, major: 18, minor: 7)])
    expect(r.fingers.count == 1, "fast swipe stays a finger")
}

func testPalmIsSticky() {
    var f = PalmFilter()
    _ = f.filter([c(1, 0.5, 0.5, major: 14, minor: 12)])
    let r = f.filter([c(1, 0.5, 0.5, major: 8, minor: 6)])
    expect(r.fingers.isEmpty, "palm stays palm")
    expect(r.newPalms == 0, "not a new palm")
}

func testIdReuseAfterLift() {
    var f = PalmFilter()
    _ = f.filter([c(1, 0.5, 0.5, major: 14, minor: 12)])
    _ = f.filter([])
    let r = f.filter([c(1, 0.5, 0.5, major: 8, minor: 6)])
    expect(r.fingers.count == 1, "reused id is a finger")
}

func testIdForgottenWhenAbsent() {
    var f = PalmFilter()
    _ = f.filter([c(1, 0.3, 0.5, major: 14, minor: 12), c(2, 0.6, 0.5)])
    _ = f.filter([c(2, 0.6, 0.5)])
    let r = f.filter([c(1, 0.3, 0.5, major: 8, minor: 6), c(2, 0.6, 0.5)])
    expect(r.fingers.count == 2, "id 1 forgotten while absent, got \(r.fingers.count)")
}

func testFingerGrowingIntoPalmWithdraws() {
    var f = PalmFilter()
    _ = f.filter([c(1, 0.5, 0.5)])
    let r = f.filter([c(1, 0.5, 0.5, major: 14, minor: 11)])
    expect(r.withdrewFinger, "withdrewFinger")
    expect(r.fingers.isEmpty, "no fingers")
}

func testZeroShapeIsFinger() {
    var f = PalmFilter()
    let r = f.filter([c(1, 0.5, 0.5, major: 0, minor: 0)])
    expect(r.fingers.count == 1, "zero shape is a finger")
    expect(r.newPalms == 0, "no palms")
}

func testFingersBesidePalmSurvive() {
    var f = PalmFilter()
    let r = f.filter([
        c(1, 0.2, 0.5, major: 20, minor: 12),
        c(2, 0.4, 0.5), c(3, 0.5, 0.5), c(4, 0.6, 0.5),
    ])
    expect(r.fingers.count == 3, "three fingers survive, got \(r.fingers.count)")
}

// MARK: - Run

test("testParseKeepsOnlyTouchingStates", testParseKeepsOnlyTouchingStates)
test("testParseEmptyFrame", testParseEmptyFrame)
test("testParseRejectsNilPointerWithCount", testParseRejectsNilPointerWithCount)
test("testParseRejectsTooManyContacts", testParseRejectsTooManyContacts)
test("testParseRejectsBadState", testParseRejectsBadState)
test("testParseRejectsOutOfRangePosition", testParseRejectsOutOfRangePosition)
test("testParseDropsImplausibleSize", testParseDropsImplausibleSize)
test("testParseSkipsHoverWithBadPosition", testParseSkipsHoverWithBadPosition)
test("testWideContactIsPalm", testWideContactIsPalm)
test("testLongStillContactIsPalm", testLongStillContactIsPalm)
test("testLongMovingContactStaysFinger", testLongMovingContactStaysFinger)
test("testPalmIsSticky", testPalmIsSticky)
test("testIdReuseAfterLift", testIdReuseAfterLift)
test("testIdForgottenWhenAbsent", testIdForgottenWhenAbsent)
test("testFingerGrowingIntoPalmWithdraws", testFingerGrowingIntoPalmWithdraws)
test("testZeroShapeIsFinger", testZeroShapeIsFinger)
test("testFingersBesidePalmSurvive", testFingersBesidePalmSurvive)

print("\(totalPassed) passed, \(totalFailed) failed")
exit(totalFailed == 0 ? 0 : 1)
