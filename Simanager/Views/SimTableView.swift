import SwiftUI
import SimanagerCore

struct SimTableView: View {
    @Environment(AppModel.self) private var model

    /// Fixed columns. Name, Checkout and Tied to are flexible: they share whatever width the window has, so the
    /// table never scrolls sideways.
    static let columns = (runtime: 96.0, memory: 72.0, up: 60.0, actions: 230.0)
    /// The width the window opens at: room for the flexible columns to show their text unwrapped.
    static let contentWidth = 1560.0

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            header.padding(10)
            if let error = model.lanesError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).padding([.horizontal, .bottom], 10)
            }
            Table(model.shown?.rows ?? []) {
                TableColumn("Name") { row in
                    VStack(alignment: .leading) {
                        Text(row.device.name)
                        if row.device.isTestClone { Text("test clone").font(.caption).foregroundStyle(.secondary) }
                    }
                }.width(min: 170, max: .infinity)
                TableColumn("Runtime") { Text($0.device.runtime) }.width(Self.columns.runtime)
                TableColumn("Memory") { Text(Format.memory($0.footprint)).monospacedDigit() }.width(Self.columns.memory)
                TableColumn("Up") { Text(Format.uptime($0.uptime)).monospacedDigit() }.width(Self.columns.up)
                TableColumn("Checkout") { row in
                    if let c = row.checkout {
                        VStack(alignment: .leading) {
                            Text(Format.path(c.path)).lineLimit(1).truncationMode(.head)
                            Text(c.branch ?? "detached").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }.help("\(c.path) (\(c.branch ?? "detached"))")
                    } else { Text("—") }
                }.width(min: 150, max: .infinity)
                TableColumn("Tied to") { EvidenceList(model: model, row: $0) }.width(min: 240, max: .infinity)
                TableColumn("") { RowActions(model: model, row: $0) }.width(Self.columns.actions)
            }
            ForEach(model.apps) { app in
                HStack {
                    Image(systemName: "macwindow")
                    Text(app.name)
                    Text("pid \(app.id)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit") { model.quitRequest = app }
                }.padding(.horizontal, 10).padding(.vertical, 4)
            }
            Divider()
            ActivityView().padding(10)
        }
        .frame(minWidth: 1080, minHeight: 320)
        .sheet(item: $model.confirmRequest) { ConfirmSheet(request: $0) }
        .sheet(item: $model.bulkAction) { BulkSheet(action: $0, rows: model.shown?.rows ?? []) }
        .alert("Quit \(model.quitRequest?.name ?? "")?", isPresented: Binding(get: { model.quitRequest != nil }, set: { if !$0 { model.quitRequest = nil } }),
               presenting: model.quitRequest) { app in
            Button("Cancel", role: .cancel) {}
            Button("Quit", role: .destructive) { model.quit(app) }
        } message: { _ in Text("Quitting may shut down simulators this app booted itself.") }
    }

    private var header: some View {
        HStack {
            if let s = model.shown {
                Text("\(s.rows.count) booted · \(Format.gigabytes(s.totalFootprint)) GB in simulators")
            } else {
                Text("Reading simulators…")
            }
            if let stats = model.stats {
                Text("· swap \(Format.gigabytes(stats.swapUsed)) / \(Format.gigabytes(stats.swapTotal)) GB")
                    .foregroundStyle(stats.swapFraction > 0.8 ? .orange : .primary)
                    .help("Swap: memory macOS has moved out of RAM onto disk, used / total. Near full means the Mac is out of memory. Orange above 80%.")
            }
            if model.isStale { Text("· stale — \(model.failedProbes.isEmpty ? "a probe" : model.failedProbes.joined(separator: ", ")) failed").foregroundStyle(.orange) }
            Spacer()
            if model.isScanning { ProgressView().controlSize(.small) }
            Button("Scan history") { Task { await model.scanHistory(for: nil) } }.disabled(model.isScanning)
                .help("Finds the last command a Claude session ran against each simulator (last 7 days)")
            Menu("All") {
                Button("Shut down all…") { model.bulkAction = .shutdown }
                Button("Delete all…") { model.bulkAction = .delete }
            }.fixedSize().disabled(model.isStale)       // "all" picks by owner; after a failed probe owners are unknown
            Button { Task { await model.refreshNow() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Refreshes every 5 s on its own")
        }
    }
}

struct RowActions: View {
    let model: AppModel     // passed in for the same reason as EvidenceList
    let row: SimRow

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack {
                Button("Shut down") { model.confirmRequest = ConfirmRequest(row: row, action: .shutdown) }
                Button("Delete") { model.confirmRequest = ConfirmRequest(row: row, action: .delete) }
                Toggle(isOn: Binding(get: { model.pinned.contains(row.id) }, set: { model.setPinned(row.id, $0) })) {
                    Image(systemName: model.pinned.contains(row.id) ? "pin.fill" : "pin")
                }.toggleStyle(.button).help("Keep: auto-reaping never touches it and \"All\" skips it")
            }
            if let error = model.rowErrors[row.id] { Text(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
        }
    }
}

/// One line per piece of live evidence. A session shown by both kinds is listed once; bare shells share one line.
func evidenceLines(_ live: [Evidence]) -> [String] {
    var seen: Set<String> = [], shells: [String] = []
    var out = live.compactMap { evidence -> String? in
        switch evidence {
        case .direct(let pid, let command, let session):
            let tool = command.split(separator: " ").first.map { (String($0) as NSString).lastPathComponent } ?? "process"
            return "\(session?.label ?? "pid \(pid)") · running \(tool)"
        case .checkout(let session):
            if session.kind == .shell, session.zellijSession == nil { shells.append(session.tty ?? String(session.pid)); return nil }
            return session.label
        case .history: return nil
        }
    }.filter { seen.insert($0).inserted }
    if !shells.isEmpty { out.append((shells.count == 1 ? "shell " : "\(shells.count) shells in the checkout: ") + shells.joined(separator: ", ")) }
    return out
}

struct DotLabel: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon.font(.system(size: 7)).foregroundStyle(color)
            configuration.title
        }
    }
}
