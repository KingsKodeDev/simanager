import SwiftUI
import SimanagerCore

/// One table row, with a value for each column to sort by.
struct SimLine: Identifiable {
    let row: SimRow
    let kept: Bool
    let hit: HistoryHit?

    var id: String { row.id }
    var name: String { row.device.name }
    var memory: UInt64 { row.footprint ?? 0 }
    var uptime: TimeInterval { row.uptime ?? 0 }
    var checkout: String { row.checkout?.path ?? "" }
    /// In use, then unused, then kept.
    var status: Int { row.hasLiveOwner ? 0 : kept ? 2 : 1 }
    var lastCommand: Date { hit?.time ?? .distantPast }
}

struct SimTableView: View {
    @Environment(AppModel.self) private var model
    /// Biggest first: the question the window answers is what to shut down.
    @State private var sortOrder = [KeyPathComparator(\SimLine.memory, order: .reverse)]

    /// Fixed columns. The rest are flexible: they share whatever width the window has, so the table never scrolls sideways.
    static let columns = (memory: 76.0, up: 64.0, actions: 300.0)
    /// The width the window opens at: room for the flexible columns to show their text unwrapped.
    static let contentWidth = 1560.0

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                MemoryTile()
                VStack(spacing: 14) {
                    SwapTile()
                    ThermalTile()
                }.frame(width: 360)
            }.fixedSize(horizontal: false, vertical: true)
            if let error = model.lanesError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            simulators
            ForEach(model.apps) { app in
                HStack {
                    Image(systemName: "macwindow")
                    Text(app.name).fontWeight(.medium)
                    Text("pid \(app.id) · quitting it may shut down simulators it booted itself").foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit \(app.name)") { model.quitRequest = app }
                }.tile(padding: 10)
            }
            ActivityView().tile(padding: 10)
        }
        .padding(16)
        .frame(minWidth: 1200, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationSubtitle("Refreshes every 5 s")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Task { await model.refreshNow() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Refresh now. It also refreshes every 5 s on its own")
                Button { Task { await model.scanHistory(for: nil) } } label: {
                    Label("Check recent use", systemImage: "clock.arrow.circlepath").labelStyle(.titleAndIcon)
                }
                .disabled(model.isScanning)
                .help("Reads the last 7 days of Claude transcripts for the last command run against each simulator")
                Button { model.cleanUpOpen = true } label: {
                    Label(model.unused.isEmpty ? "Clean up…" : "Clean up \(model.unused.count) unused…", systemImage: "power").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isStale)        // clean-up picks by owner; after a failed probe owners are unknown
                .help("Shut down or delete the simulators nothing is using")
            }
        }
        .sheet(item: $model.confirmRequest) { ConfirmSheet(request: $0) }
        .sheet(isPresented: $model.cleanUpOpen) { CleanUpSheet(rows: model.shown?.rows ?? []) }
        .alert("Quit \(model.quitRequest?.name ?? "")?", isPresented: Binding(get: { model.quitRequest != nil }, set: { if !$0 { model.quitRequest = nil } }),
               presenting: model.quitRequest) { app in
            Button("Cancel", role: .cancel) {}
            Button("Quit", role: .destructive) { model.quit(app) }
        } message: { _ in Text("Quitting may shut down simulators this app booted itself.") }
    }

    private var lines: [SimLine] {
        (model.shown?.rows ?? []).map { SimLine(row: $0, kept: model.pinned.contains($0.id), hit: model.history[$0.id]) }
            .sorted(using: sortOrder)
    }

    private var simulators: some View {
        VStack(alignment: .leading, spacing: 0) {
            listHeader.padding(.horizontal, 12).padding(.vertical, 10)
            Divider()
            Table(lines, sortOrder: $sortOrder) {
                TableColumn("Simulator", value: \.name) { line in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.name).fontWeight(.medium)
                        Text(line.row.device.runtime + (line.row.device.isTestClone ? " · test clone" : "")).font(.callout).foregroundStyle(.secondary)
                    }
                }.width(min: 180, max: .infinity)
                TableColumn("Memory", value: \.memory) { Text(Format.memory($0.row.footprint)).monospacedDigit() }.width(Self.columns.memory)
                TableColumn("Up", value: \.uptime) { Text(Format.uptime($0.row.uptime)).monospacedDigit() }.width(Self.columns.up)
                TableColumn("Checkout", value: \.checkout) { line in
                    if let c = line.row.checkout {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Format.path(c.path)).lineLimit(1).truncationMode(.head)
                            Text(c.branch ?? "detached").font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }.help("\(c.path) (\(c.branch ?? "detached"))")
                    } else { Text("No checkout").foregroundStyle(.secondary) }
                }.width(min: 150, max: .infinity)
                TableColumn("Status", value: \.status) { StatusCell(model: model, row: $0.row) }.width(min: 230, max: .infinity)
                TableColumn("Last Claude command", value: \.lastCommand) { LastCommandCell(model: model, row: $0.row) }.width(min: 170, max: .infinity)
                TableColumn("") { RowActions(model: model, row: $0.row) }.width(Self.columns.actions)
            }
            .frame(minHeight: 200)
            Divider()
            HStack(spacing: 20) {
                Text("**Keep** protects a simulator: auto clean-up and Clean up both skip it.")
                Text("**Check recent use** reads 7 days of Claude transcripts for the last command run against each simulator.")
                if let checked = model.historyScannedAt.values.max() {
                    Text("Last checked \(checked.formatted(date: .omitted, time: .shortened)).")
                }
            }
            .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .panel()
    }

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let rows = model.shown?.rows {
                let inUse = rows.filter(\.hasLiveOwner).count
                // Kept is counted on its own: a kept simulator is also in use or unused.
                let kept = rows.filter { model.pinned.contains($0.id) }.count
                Text("\(rows.count) booted simulators").font(.headline)
                Text("\(inUse) in use · \(rows.count - inUse) unused · \(kept) kept").foregroundStyle(.secondary)
            } else {
                Text("Reading simulators…").font(.headline)
            }
            if model.isStale {
                Text("Stale: \(model.failedProbes.isEmpty ? "a probe" : model.failedProbes.joined(separator: ", ")) failed").foregroundStyle(.orange)
            }
            Spacer()
            if model.isScanning { ProgressView().controlSize(.small) }
            Toggle("Auto clean-up after \(Int(model.reapSettings.idlePeriod / 60)) min unused",
                   isOn: Binding(get: { model.reapSettings.enabled }, set: { on in model.updateReapSettings { $0.enabled = on } }))
                .toggleStyle(.switch).controlSize(.small)
                .help("Shuts down or deletes a simulator once nothing has used it for that long. Kept simulators are skipped.")
        }
    }
}

struct RowActions: View {
    let model: AppModel     // passed in for the same reason as StatusCell
    let row: SimRow

    var body: some View {
        let kept = model.pinned.contains(row.id)
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 8) {
                Toggle(isOn: Binding(get: { kept }, set: { model.setPinned(row.id, $0) })) {
                    Label(kept ? "Kept" : "Keep", systemImage: kept ? "lock.fill" : "lock.open")
                }.toggleStyle(.button).help("Keep protects it: auto clean-up and Clean up both skip it")
                Button { model.confirmRequest = ConfirmRequest(row: row, action: .shutdown) } label: {
                    Label(SimAction.shutdown.title, systemImage: SimAction.shutdown.icon)
                }
                Button(role: .destructive) { model.confirmRequest = ConfirmRequest(row: row, action: .delete) } label: {
                    Label(SimAction.delete.title, systemImage: SimAction.delete.icon).foregroundStyle(.red)
                }
            }
            .buttonStyle(.bordered).labelStyle(.titleAndIcon)
            if let error = model.rowErrors[row.id] { Text(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
        }
    }
}
