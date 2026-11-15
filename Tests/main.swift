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

// MARK: - Tap recognizer tests

func fingers(_ n: Int, dx: Double = 0) -> [TouchContact] {
    (0..<n).map { i in
        let id = i + 1
        return TouchContact(id: Int32(id), x: 0.2 * Double(id) + dx, y: 0.5, major: 8, minor: 7)
    }
}

func tapConfig() -> TapConfig {
    var config = TapConfig()
    config.enabledCounts = [3, 4]
    return config
}

func rejection(_ v: TapVerdict?) -> (fingers: Int, reason: RejectReason, duration: Double, travel: Double)? {
    if case let .rejected(fingers, reason, duration, travel)? = v { return (fingers, reason, duration, travel) }
    return nil
}

func testThreeFingerTap() {
    var r = MultiFingerTapRecognizer()
    let cfg = tapConfig()
    expect(r.process(contacts: fingers(3), timestamp: 0.00, config: cfg) == nil, "start nil")
    expect(r.process(contacts: fingers(3), timestamp: 0.05, config: cfg) == nil, "hold nil")
    expect(r.process(contacts: fingers(2), timestamp: 0.06, config: cfg) == .tap(fingers: 3), "tap")
}

func testTooLongRejected() {
    var r = MultiFingerTapRecognizer()
    let cfg = tapConfig()
    _ = r.process(contacts: fingers(3), timestamp: 0.00, config: cfg)
    let v = rejection(r.process(contacts: fingers(2), timestamp: 0.20, config: cfg))
    expect(v?.reason == .duration, "duration")
    expect(v?.fingers == 3, "fingers")
}

func testTooShortRejected() {
    var r = MultiFingerTapRecognizer()
    let cfg = tapConfig()
    _ = r.process(contacts: fingers(3), timestamp: 0.00, config: cfg)
    expect(rejection(r.process(contacts: fingers(2), timestamp: 0.01, config: cfg))?.reason == .duration, "duration")
}

func testMovementRejected() {
    var r = MultiFingerTapRecognizer()
    let cfg = tapConfig()
    _ = r.process(contacts: fingers(3), timestamp: 0.00, config: cfg)
    let base = fingers(3)
    let moved = [base[0], TouchContact(id: 2, x: base[1].x + 0.05, y: 0.5, major: 8, minor: 7), base[2]]
    _ = r.process(contacts: moved, timestamp: 0.04, config: cfg)
    expect(rejection(r.process(contacts: fingers(2), timestamp: 0.06, config: cfg))?.reason == .movement, "movement")
}

func testUniformSmallMovementAccepted() {
    var r = MultiFingerTapRecognizer()
    let cfg = tapConfig()
    _ = r.process(contacts: fingers(3), timestamp: 0.00, config: cfg)
    _ = r.process(contacts: fingers(3, dx: 0.01), timestamp: 0.04, config: cfg)
    expect(r.process(contacts: fingers(2, dx: 0.01), timestamp: 0.06, config: cfg) == .tap(fingers: 3), "tap")
}

func testUpgradeResetsTimer() {
    var r = MultiFingerTapRecognizer()
    let cfg = tapConfig()
    _ = r.process(contacts: fingers(3), timestamp: 0.00, config: cfg)
    _ = r.process(contacts: fingers(4), timestamp: 0.10, config: cfg)
    expect(r.process(contacts: fingers(3), timestamp: 0.15, config: cfg) == .tap(fingers: 4), "tap 4")
}

func testNoSecondVerdictUntilFullLift() {
    var r = MultiFingerTapRecognizer()
    let cfg = tapConfig()
    _ = r.process(contacts: fingers(4), timestamp: 0.00, config: cfg)
    expect(r.process(contacts: fingers(3), timestamp: 0.05, config: cfg) == .tap(fingers: 4), "tap 4")
    expect(r.process(contacts: fingers(3), timestamp: 0.06, config: cfg) == nil, "3 nil")
    expect(r.process(contacts: fingers(2), timestamp: 0.09, config: cfg) == nil, "2 nil")
    expect(r.process(contacts: fingers(1), timestamp: 0.10, config: cfg) == nil, "1 nil")
    expect(r.process(contacts: [], timestamp: 0.11, config: cfg) == nil, "0 nil")
    _ = r.process(contacts: fingers(3), timestamp: 1.00, config: cfg)
    expect(r.process(contacts: fingers(2), timestamp: 1.06, config: cfg) == .tap(fingers: 3), "fresh tap")
}

func testNotConfiguredRejected() {
    var r = MultiFingerTapRecognizer()
    var cfg = tapConfig()
    cfg.enabledCounts = [3]
    _ = r.process(contacts: fingers(5), timestamp: 0.00, config: cfg)
    let v = rejection(r.process(contacts: fingers(4), timestamp: 0.05, config: cfg))
    expect(v?.reason == .notConfigured, "notConfigured")
    expect(v?.fingers == 5, "fingers")
}

func testTypingCooldownRejects() {
    var r = MultiFingerTapRecognizer()
    let cfg = tapConfig()
    r.keyDown(at: 1.0)
    _ = r.process(contacts: fingers(3), timestamp: 1.20, config: cfg)
    expect(rejection(r.process(contacts: fingers(2), timestamp: 1.26, config: cfg))?.reason == .typing, "typing")
    _ = r.process(contacts: [], timestamp: 1.30, config: cfg)
    _ = r.process(contacts: fingers(3), timestamp: 1.50, config: cfg)
    expect(r.process(contacts: fingers(2), timestamp: 1.56, config: cfg) == .tap(fingers: 3), "tap after cooldown")
}

func testKeyDownDuringTouchRejects() {
    var r = MultiFingerTapRecognizer()
    let cfg = tapConfig()
    _ = r.process(contacts: fingers(3), timestamp: 2.00, config: cfg)
    r.keyDown(at: 2.03)
    expect(rejection(r.process(contacts: fingers(2), timestamp: 2.06, config: cfg))?.reason == .typing, "typing")
}

func testCooldownZeroDisablesTyping() {
    var r = MultiFingerTapRecognizer()
    var cfg = tapConfig()
    cfg.typingCooldown = 0
    r.keyDown(at: 1.0)
    _ = r.process(contacts: fingers(3), timestamp: 1.01, config: cfg)
    expect(r.process(contacts: fingers(2), timestamp: 1.07, config: cfg) == .tap(fingers: 3), "tap")
}

func testCancelBlocksUntilFullLift() {
    var r = MultiFingerTapRecognizer()
    let cfg = tapConfig()
    _ = r.process(contacts: fingers(3), timestamp: 0.00, config: cfg)
    r.cancel()
    expect(r.process(contacts: fingers(3), timestamp: 0.03, config: cfg) == nil, "3 nil")
    expect(r.process(contacts: fingers(2), timestamp: 0.06, config: cfg) == nil, "2 nil")
    expect(r.process(contacts: [], timestamp: 0.07, config: cfg) == nil, "0 nil")
    _ = r.process(contacts: fingers(3), timestamp: 1.00, config: cfg)
    expect(r.process(contacts: fingers(2), timestamp: 1.06, config: cfg) == .tap(fingers: 3), "tap")
}

func testReplacedFingerRejected() {
    var r = MultiFingerTapRecognizer()
    let cfg = tapConfig()
    func ids(_ list: [Int32]) -> [TouchContact] {
        list.map { TouchContact(id: $0, x: 0.2 * Double($0), y: 0.5, major: 8, minor: 7) }
    }
    _ = r.process(contacts: ids([1, 2, 3]), timestamp: 0.00, config: cfg)
    _ = r.process(contacts: ids([1, 2, 4]), timestamp: 0.04, config: cfg)
    expect(rejection(r.process(contacts: ids([1, 2]), timestamp: 0.06, config: cfg))?.reason == .unstable, "unstable")
}

func testTwoFingersNeverTrack() {
    var r = MultiFingerTapRecognizer()
    let cfg = tapConfig()
    expect(r.process(contacts: fingers(2), timestamp: 0.00, config: cfg) == nil, "2 nil")
    expect(r.process(contacts: fingers(1), timestamp: 0.05, config: cfg) == nil, "1 nil")
    expect(r.process(contacts: [], timestamp: 0.06, config: cfg) == nil, "0 nil")
}

func testRejectionCarriesMeasurements() {
    var r = MultiFingerTapRecognizer()
    let cfg = tapConfig()
    _ = r.process(contacts: fingers(3), timestamp: 0.00, config: cfg)
    let v = rejection(r.process(contacts: fingers(2), timestamp: 0.20, config: cfg))
    expect(v != nil && abs(v!.duration - 0.20) < 1e-9, "duration")
    expect(v?.travel == 0, "travel")
}

// MARK: - Pipeline tests

func palm() -> TouchContact { c(9, 0.5, 0.1, major: 26, minor: 16) }

func testPipelinePalmPlusThreeFingersTaps() {
    var p = TouchPipeline()
    let cfg = tapConfig()
    let o1 = p.handle(contacts: fingers(3) + [palm()], timestamp: 0.00, now: 0.00, config: cfg)
    expect(o1.palmsIgnored == 1, "palmsIgnored")
    expect(o1.palmSize == 26, "palmSize")
    expect(o1.verdict == nil, "start nil")
    _ = p.handle(contacts: fingers(3) + [palm()], timestamp: 0.05, now: 0.05, config: cfg)
    let o3 = p.handle(contacts: fingers(2) + [palm()], timestamp: 0.06, now: 0.06, config: cfg)
    expect(o3.verdict == .tap(fingers: 3), "tap")
}

func testPipelinePalmPlusTwoFingersNoTap() {
    var p = TouchPipeline()
    let cfg = tapConfig()
    let a = p.handle(contacts: fingers(2) + [palm()], timestamp: 0.00, now: 0.00, config: cfg)
    let b = p.handle(contacts: fingers(1) + [palm()], timestamp: 0.06, now: 0.06, config: cfg)
    expect(a.verdict == nil && b.verdict == nil, "no verdicts")
}

func testPipelinePalmRejectionOffCountsPalm() {
    var p = TouchPipeline()
    p.palmRejection = false
    var cfg = TapConfig()
    cfg.enabledCounts = [3]
    _ = p.handle(contacts: fingers(2) + [palm()], timestamp: 0.00, now: 0.00, config: cfg)
    let o = p.handle(contacts: fingers(1) + [palm()], timestamp: 0.06, now: 0.06, config: cfg)
    expect(o.verdict == .tap(fingers: 3), "palm counted")
}

func testPipelineStaleFrameCancels() {
    var p = TouchPipeline()
    let cfg = tapConfig()
    _ = p.handle(contacts: fingers(3), timestamp: 0.00, now: 0.00, config: cfg)
    let stale = p.handle(contacts: fingers(3), timestamp: 0.04, now: 0.30, config: cfg)
    expect(stale.cancelled == "stale", "stale")
    expect(p.handle(contacts: fingers(2), timestamp: 0.06, now: 0.06, config: cfg).verdict == nil, "blocked")
    _ = p.handle(contacts: [], timestamp: 0.07, now: 0.07, config: cfg)
    _ = p.handle(contacts: fingers(3), timestamp: 1.00, now: 1.00, config: cfg)
    expect(p.handle(contacts: fingers(2), timestamp: 1.06, now: 1.06, config: cfg).verdict == .tap(fingers: 3), "fresh tap")
}

func testPipelineMalformedCancels() {
    var p = TouchPipeline()
    let cfg = tapConfig()
    _ = p.handle(contacts: fingers(3), timestamp: 0.00, now: 0.00, config: cfg)
    expect(p.handle(contacts: nil, timestamp: 0.03, now: 0.03, config: cfg).cancelled == "malformed", "malformed")
    expect(p.handle(contacts: fingers(2), timestamp: 0.06, now: 0.06, config: cfg).verdict == nil, "blocked")
}

func testPipelineFingerBecomingPalmCancels() {
    var p = TouchPipeline()
    let cfg = tapConfig()
    _ = p.handle(contacts: fingers(3), timestamp: 0.00, now: 0.00, config: cfg)
    var grown = fingers(3)
    grown[0] = c(1, grown[0].x, grown[0].y, major: 14, minor: 12)
    expect(p.handle(contacts: grown, timestamp: 0.03, now: 0.03, config: cfg).cancelled == "palm", "palm")
    expect(p.handle(contacts: fingers(2), timestamp: 0.06, now: 0.06, config: cfg).verdict == nil, "blocked")
}

func testPipelineKeyDownForwards() {
    var p = TouchPipeline()
    let cfg = tapConfig()
    p.keyDown(at: 1.0)
    _ = p.handle(contacts: fingers(3), timestamp: 1.10, now: 1.10, config: cfg)
    expect(rejection(p.handle(contacts: fingers(2), timestamp: 1.16, now: 1.16, config: cfg).verdict)?.reason == .typing, "typing")
}

// MARK: - Run

func testHapticGateFirstPulseAllowed() {
    var g = HapticGate()
    expect(g.allow(at: 10.0), "first pulse allowed")
}

func testHapticGateBlocksWithinInterval() {
    var g = HapticGate()
    _ = g.allow(at: 10.0)
    expect(!g.allow(at: 10.03), "within interval blocked")
    expect(g.allow(at: 10.05), "refused call must not move the window")
}

func testHapticGateRejectsNonFiniteTime() {
    var g = HapticGate()
    expect(!g.allow(at: .nan), "nan refused")
    expect(g.allow(at: 1.0), "later finite time allowed")
}

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
test("testThreeFingerTap", testThreeFingerTap)
test("testTooLongRejected", testTooLongRejected)
test("testTooShortRejected", testTooShortRejected)
test("testMovementRejected", testMovementRejected)
test("testUniformSmallMovementAccepted", testUniformSmallMovementAccepted)
test("testUpgradeResetsTimer", testUpgradeResetsTimer)
test("testNoSecondVerdictUntilFullLift", testNoSecondVerdictUntilFullLift)
test("testNotConfiguredRejected", testNotConfiguredRejected)
test("testTypingCooldownRejects", testTypingCooldownRejects)
test("testKeyDownDuringTouchRejects", testKeyDownDuringTouchRejects)
test("testCooldownZeroDisablesTyping", testCooldownZeroDisablesTyping)
test("testCancelBlocksUntilFullLift", testCancelBlocksUntilFullLift)
test("testReplacedFingerRejected", testReplacedFingerRejected)
test("testTwoFingersNeverTrack", testTwoFingersNeverTrack)
test("testRejectionCarriesMeasurements", testRejectionCarriesMeasurements)
test("testPipelinePalmPlusThreeFingersTaps", testPipelinePalmPlusThreeFingersTaps)
test("testPipelinePalmPlusTwoFingersNoTap", testPipelinePalmPlusTwoFingersNoTap)
test("testPipelinePalmRejectionOffCountsPalm", testPipelinePalmRejectionOffCountsPalm)
test("testPipelineStaleFrameCancels", testPipelineStaleFrameCancels)
test("testPipelineMalformedCancels", testPipelineMalformedCancels)
test("testPipelineFingerBecomingPalmCancels", testPipelineFingerBecomingPalmCancels)
test("testPipelineKeyDownForwards", testPipelineKeyDownForwards)
test("testHapticGateFirstPulseAllowed", testHapticGateFirstPulseAllowed)
test("testHapticGateBlocksWithinInterval", testHapticGateBlocksWithinInterval)
test("testHapticGateRejectsNonFiniteTime", testHapticGateRejectsNonFiniteTime)

print("\(totalPassed) passed, \(totalFailed) failed")
exit(totalFailed == 0 ? 0 : 1)
