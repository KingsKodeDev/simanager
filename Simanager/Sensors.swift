import Foundation
import IOKit
import SimanagerCore

struct SensorReading: Sendable {
    /// The hottest CPU core sensor; `nil` when this Mac exposes none this reader recognises.
    let cpuCelsius: Double?
    /// Empty on a Mac with no fan.
    let fans: [Fan]
}

/// Reads temperature and fan speed from the SMC, the Mac's hardware controller. macOS has no public API for
/// either; this is the interface fan utilities use, and it is one more thing the sandbox would forbid.
actor Sensors {
    private var connection: io_connect_t = 0
    private var opened = false
    private var cpuKeys: [UInt32] = []
    private var fans: [(actual: UInt32, max: Double)] = []

    /// `nil` when the SMC cannot be opened at all.
    func read() -> SensorReading? {
        if !opened { open() }
        guard connection != 0 else { return nil }
        return SensorReading(cpuCelsius: cpuKeys.compactMap(float).filter(Self.plausible).max(),
                             fans: fans.compactMap { fan in float(fan.actual).map { Fan(rpm: $0, max: fan.max) } })
    }

    private static func plausible(_ celsius: Double) -> Bool { celsius > 0 && celsius < 150 }

    private func open() {
        opened = true
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { connection = 0; return }

        // shortcut: CPU sensors are found by the `Tp` prefix Apple silicon uses, so an Intel Mac (TC0P, a different
        // number format) shows no temperature; add its keys when one needs it.
        let count = value(Self.code("#KEY")).map { $0.bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } } ?? 0
        for index in 0..<count {
            var input = SMCKeyData()
            input.data8 = 8         // key at index
            input.data32 = index
            guard let key = call(&input)?.key, key >> 16 == Self.code("Tp"), float(key).map(Self.plausible) == true else { continue }
            cpuKeys.append(key)
        }
        for index in 0..<Int(value(Self.code("FNum"))?.bytes.first ?? 0) {
            guard let max = float(Self.code("F\(index)Mx")) else { continue }
            fans.append((Self.code("F\(index)Ac"), max))
        }
    }

    private static func code(_ name: String) -> UInt32 { name.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    /// A key's value when it is a little-endian 32-bit float, the format Apple silicon reports temperatures and fans in.
    private func float(_ key: UInt32) -> Double? {
        guard let v = value(key), v.type == Self.code("flt "), v.bytes.count == 4 else { return nil }
        return Double(v.bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
    }

    private func value(_ key: UInt32) -> (type: UInt32, bytes: [UInt8])? {
        var ask = SMCKeyData()
        ask.key = key
        ask.data8 = 9               // key info: size and type
        guard let info = call(&ask)?.keyInfo, info.dataSize <= 32 else { return nil }
        var input = SMCKeyData()
        input.key = key
        input.keyInfo.dataSize = info.dataSize
        input.data8 = 5             // read
        guard let output = call(&input) else { return nil }
        return (info.dataType, withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.dataSize))) })
    }

    private func call(_ input: inout SMCKeyData) -> SMCKeyData? {
        var output = SMCKeyData()
        var size = MemoryLayout<SMCKeyData>.size
        let status = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCKeyData>.size, &output, &size)
        return status == kIOReturnSuccess && output.result == 0 ? output : nil
    }
}

/// The SMC's request and reply, laid out as its driver expects: 80 bytes. `padding` stands where C pads `keyInfo`.
private struct SMCKeyData {
    struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
    struct PowerLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, memory: UInt32 = 0 }
    struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
    typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

    var key: UInt32 = 0
    var version = Version()
    var powerLimit = PowerLimit()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}
