import SwiftUI
import SimanagerCore

/// What is using a simulator right now: a chip, one line per live session, then what auto clean-up will do with it.
struct StatusCell: View {
    // Passed in, not read from the environment: Table evaluates cells outside the window's environment
    // when rows come and go, and a missing Observable there is a crash.
    let model: AppModel
    let row: SimRow

    private var kept: Bool { model.pinned.contains(row.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if row.hasLiveOwner { Chip("In use", .good) }
                // After a failed probe "no evidence" proves nothing, so it is not called unused.
                else if model.isStale { Chip("Owner unknown", .warning) }
                else if !kept { Chip("Unused", .warning) }
                if kept { Chip("Kept", .kept) }
            }
            ForEach(evidenceLines(row.live) + notes, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
        }
    }

    private var notes: [String] {
        guard !row.hasLiveOwner else { return [] }
        if model.isStale { return ["A probe failed, so it may still be in use"] }
        var out = row.footprint == nil ? ["No process (stale boot state)"] : []
        if kept {
            out.append("Never cleaned up automatically")
        } else if !model.reapSettings.enabled {
            out.append("Auto clean-up is off")
        } else if let note = model.cleanUpNote(row.id) {
            out.append("Auto clean-up " + note)
        }
        return out
    }
}

/// The last command a Claude session ran against a simulator, as found by "Check recent use".
struct LastCommandCell: View {
    let model: AppModel
    let row: SimRow

    var body: some View {
        if let hit = model.history[row.id] {
            VStack(alignment: .leading, spacing: 3) {
                Text(hit.time.formatted(.dateTime.day().month(.abbreviated).hour().minute())).monospacedDigit()
                Text("“\(hit.sessionName ?? String(hit.sessionID.prefix(8)))” · \(hit.sessionRunning ? "still running" : "session ended")")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }.help(hit.command)
        } else {
            Text(model.historyScannedAt[row.id] == nil ? "Not checked" : "None in the last 7 days").foregroundStyle(.secondary)
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
