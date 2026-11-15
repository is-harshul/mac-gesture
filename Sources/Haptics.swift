// Portions adapted from Kinara (https://github.com/0x1p0/kinara), MIT License, Copyright (c) 2026 0x1p0.
import AppKit

enum HapticStyle: String, CaseIterable {
    case off, soft, standard, crisp, strong

    var label: String {
        switch self {
        case .off: return "Off"
        case .soft: return "Soft"
        case .standard: return "Standard"
        case .crisp: return "Crisp"
        case .strong: return "Strongest"
        }
    }
}

var hapticStyle: HapticStyle = .standard

// MARK: - Private actuator bridge (all symbols optional)

private typealias DeviceIDFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
private typealias ActuatorCreateFn = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
private typealias ActuatorOpenFn = @convention(c) (UnsafeMutableRawPointer) -> Int32
private typealias ActuatorActuateFn = @convention(c) (UnsafeMutableRawPointer, Int32, UInt32, Float, Float) -> Int32

private struct ActuatorAPI {
    let deviceID: DeviceIDFn
    let create: ActuatorCreateFn
    let open: ActuatorOpenFn
    let actuate: ActuatorActuateFn
}

private let actuatorAPI: ActuatorAPI? = {
    guard let h = mtFramework,
          let a = dlsym(h, "MTDeviceGetDeviceID"),
          let b = dlsym(h, "MTActuatorCreateFromDeviceID"),
          let c = dlsym(h, "MTActuatorOpen"),
          let d = dlsym(h, "MTActuatorActuate") else { return nil }
    return ActuatorAPI(deviceID: unsafeBitCast(a, to: DeviceIDFn.self),
                       create: unsafeBitCast(b, to: ActuatorCreateFn.self),
                       open: unsafeBitCast(c, to: ActuatorOpenFn.self),
                       actuate: unsafeBitCast(d, to: ActuatorActuateFn.self))
}()

enum HapticOutput {
    private static var gate = HapticGate()
    private static var actuators: [UInt64: UnsafeMutableRawPointer] = [:]
    private static let maxCachedActuators = 4

    /// Main thread only.
    static func play(_ style: HapticStyle) {
        guard style != .off else { return }
        guard gate.allow(at: ProcessInfo.processInfo.systemUptime) else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch style {
        case .off: return
        case .soft: pattern = .alignment
        case .standard: pattern = .generic
        case .crisp: pattern = .levelChange
        case .strong:
            if fireActuator() { return }
            pattern = .levelChange
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    static func forgetActuators() {
        for (_, ptr) in actuators { Unmanaged<AnyObject>.fromOpaque(ptr).release() }
        actuators.removeAll()
    }

    // MARK: Private actuator

    private static func fireActuator() -> Bool {
        guard let api = actuatorAPI else { return false }
        if let device = lastTouchedDevice, let act = actuator(for: device, api: api) {
            return actuate(act, api: api)
        }
        // No touch yet (settings preview): first device whose actuator opens.
        let list = _MTDeviceCreateList()
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            if let act = actuator(for: device, api: api) {
                return actuate(act, api: api)
            }
        }
        return false
    }

    /// Fires the actuator. A cached actuator that fails is dropped and released so the next pulse re-creates it;
    /// an uncached one (cache full) is released after the single pulse.
    private static func actuate(_ act: UnsafeMutableRawPointer, api: ActuatorAPI) -> Bool {
        let ok = api.actuate(act, 6, 0, 0, 2) == 0
        if let key = actuators.first(where: { $0.value == act })?.key {
            if !ok {
                actuators[key] = nil
                Unmanaged<AnyObject>.fromOpaque(act).release()
            }
        } else {
            Unmanaged<AnyObject>.fromOpaque(act).release()
        }
        return ok
    }

    private static func actuator(for device: UnsafeMutableRawPointer, api: ActuatorAPI) -> UnsafeMutableRawPointer? {
        var id: UInt64 = 0
        guard api.deviceID(device, &id) == 0 else { return nil }
        if let cached = actuators[id] { return cached }
        guard let act = api.create(id) else { return nil }
        guard api.open(act) == 0 else {
            Unmanaged<AnyObject>.fromOpaque(act).release()
            return nil
        }
        if actuators.count >= maxCachedActuators {
            // Cache full: returned uncached; `actuate` fires it once and releases it.
            return act
        }
        actuators[id] = act
        return act
    }
}
