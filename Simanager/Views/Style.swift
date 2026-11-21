import SwiftUI
import SimanagerCore

extension View {
    /// A rounded panel on the window background.
    func tile(padding: CGFloat = 14, fillHeight: Bool = false) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
            .panel()
    }

    func panel(radius: CGFloat = 12) -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.separator))
    }

    /// The small heading at the top of a tile.
    func tileLabel() -> some View { font(.callout.weight(.semibold)).foregroundStyle(.secondary) }
}

/// A state, said with an icon and a word as well as a colour.
struct Chip: View {
    enum Kind { case good, warning, critical, kept }
    let text: String
    let kind: Kind

    init(_ text: String, _ kind: Kind) { self.text = text; self.kind = kind }

    private var color: Color {
        switch kind { case .good: .green; case .warning: .orange; case .critical: .red; case .kept: .gray }
    }
    private var icon: String {
        switch kind {
        case .good: "circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        case .kept: "lock.fill"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: kind == .good ? 7 : 10)).foregroundStyle(color)
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(color.opacity(0.16), in: Capsule())
        .fixedSize()
    }
}

/// One value against its limit.
struct Meter: View {
    let fraction: Double
    var color: Color = .gray

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }.frame(height: 8)
    }
}

/// The Mac's memory as one bar: simulators, everything else, free.
struct MemoryBar: View {
    let split: MemorySplit
    var height: CGFloat = 28

    var body: some View {
        let parts: [(UInt64, AnyShapeStyle)] = [(split.simulators, AnyShapeStyle(Color.blue)), (split.other, AnyShapeStyle(Color.gray)),
                                                (split.free, AnyShapeStyle(.quaternary))]
        let total = Double(max(1, split.simulators + split.other + split.free))
        GeometryReader { geo in
            HStack(spacing: 2) {       // the gap, not a border, is what separates the parts
                ForEach(0..<parts.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: min(4, height / 2)).fill(parts[i].1)
                        .frame(width: max(0, (geo.size.width - 4) * Double(parts[i].0) / total))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Memory: simulators \(Format.memory(split.simulators)), everything else \(Format.memory(split.other)), free \(Format.memory(split.free))")
    }
}

/// A legend entry: the bar's colour, the part's name and its amount.
struct LegendItem: View {
    let style: AnyShapeStyle
    let name: String
    let amount: UInt64

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(style).frame(width: 10, height: 10)
            Text(name)
            Text(Format.memory(amount)).fontWeight(.semibold).monospacedDigit()
        }
    }
}

extension SimAction {
    var icon: String { self == .shutdown ? "power" : "trash" }
    /// "will be shut down", "will be deleted".
    var done: String { self == .shutdown ? "shut down" : "deleted" }
}

extension MemoryPressure {
    var chip: Chip {
        switch self {
        case .normal: Chip("Normal", .good)
        case .warning: Chip("Getting tight", .warning)
        case .critical: Chip("Out of memory", .critical)
        }
    }
}
