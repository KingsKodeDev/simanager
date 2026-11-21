import Foundation

/// How the Mac's memory divides, for the usage bar. `used` is what Activity Monitor calls Memory Used.
public struct MemorySplit: Equatable, Sendable {
    public let simulators, other, free: UInt64

    public init(total: UInt64, used: UInt64, simulators: UInt64) {
        // The three figures are read a moment apart, so each is capped by the one it is part of.
        let used = min(used, total)
        self.simulators = min(simulators, used)
        other = used - self.simulators
        free = total - used
    }
}

public enum TemperatureUnit: String, CaseIterable, Identifiable, Sendable {
    case celsius, fahrenheit
    public var id: String { rawValue }
    public var symbol: String { self == .celsius ? "°C" : "°F" }

    public func text(_ celsius: Double) -> String {
        "\(Int((self == .celsius ? celsius : celsius * 9 / 5 + 32).rounded())) \(symbol)"
    }
}

public struct Fan: Equatable, Sendable {
    public let rpm, max: Double
    public init(rpm: Double, max: Double) { self.rpm = rpm; self.max = max }
}

/// The busiest fan as a share of its top speed, 0 to 100; `nil` when no fan reports a top speed.
public func fanPercent(_ fans: [Fan]) -> Int? {
    fans.filter { $0.max > 0 }.map { min(100, Int(($0.rpm / $0.max * 100).rounded())) }.max()
}
