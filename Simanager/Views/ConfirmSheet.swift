import SwiftUI
import SimanagerCore

/// Evidence for one simulator: live lines, then the last command from history when a scan has found one.
struct EvidenceList: View {
    // Passed in, not read from the environment: Table evaluates cells outside the window's environment
    // when rows come and go, and a missing Observable there is a crash.
    let model: AppModel
    let row: SimRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(evidenceLines(row.live), id: \.self) { Label($0, systemImage: "circle.fill").labelStyle(DotLabel(color: .green)) }
            if !row.hasLiveOwner {
                // After a failed probe "no evidence" proves nothing, so it is not called "no owner".
                Label(model.isStale ? "Owner unknown — a probe failed"
                                    : "No live owner" + (row.footprint == nil ? " · no process (stale boot state)" : "") + reapNote,
                      systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            if let hit = model.history[row.id] {
                Text(historyLine(hit)).foregroundStyle(.secondary).help(hit.command)
            }
        }
    }
}

extension EvidenceList {
    /// "reaps in N min" while the idle clock runs, "kept" when pinned, nothing when auto-reap is off.
    var reapNote: String {
        guard model.reapSettings.enabled else { return "" }
        if model.pinned.contains(row.id) { return " · kept" }
        guard let seconds = model.reapsIn(row.id) else { return "" }
        return seconds <= 0 ? " · reaping" : " · reaps in \(Int((seconds / 60).rounded(.up))) min"
    }
}

func historyLine(_ hit: HistoryHit) -> String {
    let when = hit.time.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    return "last command \(when), session \"\(hit.sessionName ?? String(hit.sessionID.prefix(8)))\" (\(hit.sessionRunning ? "running" : "ended"))"
}

struct ConfirmSheet: View {
    @Environment(AppModel.self) private var model
    let request: ConfirmRequest
    @State private var scanFailed = false

    private var row: SimRow { request.row }
    private var directLabels: [String] {
        row.live.compactMap { if case .direct(let pid, _, let session) = $0 { session?.label ?? "pid \(pid)" } else { nil } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(request.action.title) \(row.device.name)?").font(.headline)
            Text("\(row.device.runtime) · \(Format.memory(row.footprint))\(row.device.isTestClone ? " · test clone" : "")").foregroundStyle(.secondary)

            EvidenceList(model: model, row: row)
            if model.isScanning { ProgressView("Checking what recently used it…").controlSize(.small) }
            if scanFailed { Text("History could not be scanned; recent use by a session elsewhere is unknown.").foregroundStyle(.orange) }

            if let first = directLabels.first {
                Text("In use right now by \(first).").foregroundStyle(.red).bold()
            } else if !row.hasLiveOwner, !model.isStale {
                Text("No live owner found. A session working from another folder may still be using it.")
            }
            StaleNotice(model: model)
            if request.action == .shutdown, row.device.runtime == "iOS 26.5" {
                Text("iOS 26.5 may not boot cleanly again after a shut down. Delete instead.").foregroundStyle(.orange)
            }
            Text(request.action == .delete ? "Deletes the device, the app installed on it and its data."
                                           : "Nothing on disk is lost. Whatever is running in it stops; the next boot is a cold boot.")
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { model.confirmRequest = nil }.keyboardShortcut(.defaultAction)
                Button(request.action.title, role: .destructive) {
                    model.confirmRequest = nil
                    Task { await model.perform(request.action, udid: row.id, automatic: false, reason: nil) }
                }.disabled(model.isScanning)        // the evidence is shown before the action is offered
            }
        }
        .padding(20).frame(width: 560)
        .task {
            if model.historyScannedAt[row.id].map({ Date().timeIntervalSince($0) > 60 }) ?? true {
                scanFailed = !(await model.scanHistory(for: [row.id]))
            }
        }
    }
}

/// Shown in confirmations when the newest refresh failed: what is listed is old, or incomplete.
struct StaleNotice: View {
    let model: AppModel
    var body: some View {
        if model.isStale {
            Text("The last refresh failed (\(model.failedProbes.joined(separator: ", "))). What is shown may be out of date, and nothing here shows a simulator is unused.")
                .foregroundStyle(.red)
        }
    }
}
