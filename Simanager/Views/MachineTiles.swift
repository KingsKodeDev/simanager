import SwiftUI
import SimanagerCore

// Each tile reads the model itself, so the once-a-second machine readings redraw the tiles and not the table.

struct MemoryTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Memory on this Mac").tileLabel()
                Spacer()
                model.stats?.pressure.chip
            }
            if let stats = model.stats {
                let split = MemorySplit(total: stats.memoryTotal, used: stats.memoryUsed, simulators: model.shown?.totalFootprint ?? 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Format.memory(split.free)) free").font(.system(size: 28, weight: .bold)).monospacedDigit()
                    Text("of \(Format.memory(stats.memoryTotal))").foregroundStyle(.secondary)
                }
                MemoryBar(split: split)
                HStack(spacing: 20) {
                    LegendItem(style: AnyShapeStyle(Color.blue), name: "Simulators", amount: split.simulators)
                    LegendItem(style: AnyShapeStyle(Color.gray), name: "Everything else", amount: split.other)
                    LegendItem(style: AnyShapeStyle(.quaternary), name: "Free", amount: split.free)
                }
                let unused = model.unused
                if !unused.isEmpty, !model.isStale {
                    Text("Cleaning up the \(unused.count) unused frees about **\(Format.memory(unused.reduce(0) { $0 + ($1.footprint ?? 0) }))**.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Reading memory…").foregroundStyle(.secondary)
            }
        }
        .tile(fillHeight: true)
    }
}

struct SwapTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let stats = model.stats
            let nearlyFull = (stats?.swapFraction ?? 0) > 0.8
            HStack {
                Text("Swap").tileLabel()
                Spacer()
                if nearlyFull { Chip("Nearly full", .warning) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // macOS creates swap only once it needs it, so there may be none at all.
                if let stats, stats.swapTotal > 0 {
                    Text(Format.memory(stats.swapUsed)).font(.title2.bold()).monospacedDigit()
                    Text("of \(Format.memory(stats.swapTotal)) used").foregroundStyle(.secondary)
                } else {
                    Text("Not in use").font(.title2.bold())
                }
            }
            Meter(fraction: stats?.swapFraction ?? 0, color: nearlyFull ? .orange : .gray)
            Text("Memory macOS has moved to disk. Near full means the Mac is out of memory.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .tile()
    }
}

struct ThermalTile: View {
    @Environment(AppModel.self) private var model
    @AppStorage(TemperatureUnit.key) private var unit = TemperatureUnit.celsius

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Temperature and fan").tileLabel()
                Spacer()
                Text("Live · 1 s").font(.caption).foregroundStyle(.secondary)
                Picker("Temperature unit", selection: $unit) {
                    ForEach(TemperatureUnit.allCases) { Text($0.symbol).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            }
            HStack(alignment: .top, spacing: 18) {
                let celsius = model.sensors?.cpuCelsius
                reading(celsius.map(unit.text) ?? "—", "CPU", fraction: (celsius ?? 0) / 100,
                        caption: celsius == nil ? "Not available on this Mac" : model.stats?.thermal.word ?? "")
                let fans = model.sensors?.fans ?? []
                let percent = fanPercent(fans)
                reading(percent.map { "\($0)%" } ?? "—", "Fan", fraction: Double(percent ?? 0) / 100,
                        caption: fans.isEmpty ? "No fan in this Mac" : fans.allSatisfy { $0.rpm < 1 } ? "Stopped"
                                 : fans.map { Int($0.rpm).formatted() }.joined(separator: " · ") + " rpm")
            }
        }
        .tile()
    }

    private func reading(_ value: String, _ name: String, fraction: Double, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.title2.bold()).monospacedDigit()
                Text(name).foregroundStyle(.secondary)
            }
            Meter(fraction: fraction)
            Text(caption).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension TemperatureUnit {
    static let key = "temperatureUnit"
}

extension ProcessInfo.ThermalState {
    /// macOS's own reading of how hot the Mac is running.
    var word: String {
        switch self {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Too hot"
        @unknown default: ""
        }
    }
}

/// The popover's version: free memory, the bar, and temperature and fan on one line.
struct MachineSummary: View {
    @Environment(AppModel.self) private var model
    @AppStorage(TemperatureUnit.key) private var unit = TemperatureUnit.celsius

    var body: some View {
        if let stats = model.stats {
            let split = MemorySplit(total: stats.memoryTotal, used: stats.memoryUsed, simulators: model.shown?.totalFootprint ?? 0)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Format.memory(split.free)) free").font(.title3.bold()).monospacedDigit()
                    Text("of \(Format.memory(stats.memoryTotal))").foregroundStyle(.secondary)
                    Spacer()
                    stats.pressure.chip
                }
                MemoryBar(split: split, height: 8)
                HStack(spacing: 14) {
                    LegendItem(style: AnyShapeStyle(Color.blue), name: "Simulators", amount: split.simulators)
                    LegendItem(style: AnyShapeStyle(Color.gray), name: "Everything else", amount: split.other)
                    Spacer()
                    if let celsius = model.sensors?.cpuCelsius {
                        Label(unit.text(celsius), systemImage: "thermometer.medium").fontWeight(.semibold).monospacedDigit()
                    }
                    if let percent = fanPercent(model.sensors?.fans ?? []) {
                        Label("\(percent)%", systemImage: "fan").fontWeight(.semibold).monospacedDigit()
                    }
                }.font(.caption)
            }
        }
    }
}
