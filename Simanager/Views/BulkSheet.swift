import SwiftUI
import SimanagerCore

struct BulkSheet: View {
    @Environment(AppModel.self) private var model
    let action: SimAction
    /// Fixed when the sheet opens: the list on screen is exactly what is acted on.
    let rows: [SimRow]
    @State private var includeInUse = false
    @State private var scanFailed = false

    private var selection: (targets: [SimRow], inUse: [SimRow]) { bulkTargets(rows: rows, pinned: model.pinned, includeInUse: includeInUse) }
    private var pinnedRows: [SimRow] { rows.filter { model.pinned.contains($0.id) } }

    var body: some View {
        let ownerless = bulkTargets(rows: rows, pinned: model.pinned, includeInUse: false).targets
        VStack(alignment: .leading, spacing: 12) {
            Text("\(action.title) all").font(.headline)
            if model.isScanning { ProgressView("Checking what recently used them…").controlSize(.small) }
            if scanFailed { Text("History could not be scanned; recent use by a session elsewhere is unknown.").foregroundStyle(.orange) }
            StaleNotice(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if ownerless.isEmpty { Text("No simulators without a live owner.").foregroundStyle(.secondary) }
                    ForEach(ownerless) { line($0) }
                    if !selection.inUse.isEmpty {
                        Divider()
                        Toggle("Also the \(selection.inUse.count) in use right now", isOn: $includeInUse)
                        ForEach(selection.inUse) { line($0).opacity(includeInUse ? 1 : 0.5) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 380)

            Text("Frees about \(Format.memory(selection.targets.reduce(0) { $0 + ($1.footprint ?? 0) })).").bold()
            if action == .delete { Text("Deletes each device, the app installed on it and its data.").foregroundStyle(.secondary) }
            if !pinnedRows.isEmpty {
                Text("Left alone (pinned): \(pinnedRows.map(\.device.name).joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.bulkAction = nil }.keyboardShortcut(.defaultAction)
                Button("\(action.title) \(selection.targets.count)", role: .destructive) {
                    let targets = selection.targets
                    model.bulkAction = nil
                    Task { await model.performAll(action, targets: targets) }
                }.disabled(model.isScanning || selection.targets.isEmpty)
            }
        }
        .padding(20).frame(width: 640)
        .task { scanFailed = !(await model.scanHistory(for: nil)) }
    }

    private func line(_ row: SimRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(row.device.name) · \(Format.memory(row.footprint))")
            EvidenceList(model: model, row: row).font(.callout).padding(.leading, 12)
        }
    }
}
