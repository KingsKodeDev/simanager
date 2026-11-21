import SwiftUI
import SimanagerCore

/// Shut down or delete every unused simulator at once. Kept ones are never taken; in-use ones only when asked.
struct CleanUpSheet: View {
    @Environment(AppModel.self) private var model
    /// Fixed when the sheet opens: the list on screen is exactly what is acted on.
    let rows: [SimRow]
    @State private var action = SimAction.shutdown
    @State private var includeInUse = false
    @State private var scanFailed = false

    private var selection: (targets: [SimRow], inUse: [SimRow]) { bulkTargets(rows: rows, pinned: model.pinned, includeInUse: includeInUse) }
    private var keptRows: [SimRow] { rows.filter { model.pinned.contains($0.id) } }

    var body: some View {
        let unused = bulkTargets(rows: rows, pinned: model.pinned, includeInUse: false).targets
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clean up simulators").font(.title3.bold())
                Text("Pick what happens to the simulators nothing is using.").font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Picker("Action", selection: $action) {
                    ForEach(SimAction.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                Text(action == .delete ? "Deletes each device, the app installed on it and its data."
                                       : "Nothing on disk is lost. Whatever is running stops; the next boot is a cold boot.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if model.isScanning { ProgressView("Checking what recently used them…").controlSize(.small) }
            if scanFailed { Text("Recent use could not be checked; use by a session elsewhere is unknown.").foregroundStyle(.orange) }
            StaleNotice(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    group("Unused · will be \(action.done)") { Text("\(unused.count) simulators").foregroundStyle(.secondary) } content: {
                        if unused.isEmpty { Text("No simulators without a live owner.").foregroundStyle(.secondary).padding(10) }
                        ForEach(unused) { line($0) }
                    }
                    if !selection.inUse.isEmpty {
                        group("In use right now · \(includeInUse ? "will be \(action.done)" : "left running")") {
                            Toggle("Include these \(selection.inUse.count)", isOn: $includeInUse).toggleStyle(.switch).controlSize(.small)
                        } content: {
                            ForEach(selection.inUse) { line($0).opacity(includeInUse ? 1 : 0.6) }
                        }
                    }
                    if !keptRows.isEmpty {
                        group("Kept · always skipped") { Text("\(keptRows.count) simulators").foregroundStyle(.secondary) } content: {
                            ForEach(keptRows) { row in
                                HStack {
                                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                                    Text(row.device.name)
                                    Spacer()
                                    Text(Format.memory(row.footprint)).monospacedDigit().foregroundStyle(.secondary)
                                }.padding(10)
                            }
                        }
                    }
                }
            }.frame(maxHeight: 400)

            Divider()
            HStack {
                Text("Frees about **\(Format.memory(selection.targets.reduce(0) { $0 + ($1.footprint ?? 0) }))**")
                Spacer()
                Button("Cancel") { model.cleanUpOpen = false }.keyboardShortcut(.defaultAction)
                Button(role: .destructive) {
                    let targets = selection.targets, chosen = action
                    model.cleanUpOpen = false
                    Task { await model.performAll(chosen, targets: targets) }
                } label: {
                    Label("\(action.title) \(selection.targets.count)", systemImage: action.icon).labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(model.isScanning || selection.targets.isEmpty)
            }
        }
        .padding(20).frame(width: 640)
        .task { scanFailed = !(await model.scanHistory(for: nil)) }
    }

    private func group(_ title: String, @ViewBuilder trailing: () -> some View, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.callout.weight(.semibold))
                Spacer()
                trailing().font(.callout)
            }.padding(.horizontal, 10).padding(.vertical, 8).background(.quaternary.opacity(0.5))
            content()
        }.panel(radius: 10)
    }

    private func line(_ row: SimRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.device.name + (row.device.isTestClone ? " · test clone" : "")).fontWeight(.medium)
                Text(summary(row)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.memory(row.footprint)).fontWeight(.medium).monospacedDigit()
        }.padding(10)
    }

    /// Who is using it now, then the last Claude command against it.
    private func summary(_ row: SimRow) -> String {
        let now = row.hasLiveOwner ? evidenceLines(row.live).joined(separator: " · ") : "Unused"
        if let hit = model.history[row.id] {
            let when = hit.time.formatted(.dateTime.day().month(.abbreviated).hour().minute())
            return "\(now) · last Claude command \(when), session \(hit.sessionRunning ? "still running" : "ended")"
        }
        return model.historyScannedAt[row.id] == nil ? now : "\(now) · no Claude command in the last 7 days"
    }
}
