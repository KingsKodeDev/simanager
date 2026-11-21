import SwiftUI
import SimanagerCore

/// The glance: the Mac's memory, then every simulator in one compact line, with the same confirmations as the window.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MachineSummary()
            let rows = model.shown?.rows ?? []
            VStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty { Text("No booted simulators").foregroundStyle(.secondary).padding(.vertical, 6) }
                ForEach(rows) { row in
                    Divider()
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.device.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                            status(row).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(Format.memory(row.footprint)).monospacedDigit()
                        Button { confirm(row, .shutdown) } label: { Label(SimAction.shutdown.title, systemImage: SimAction.shutdown.icon) }
                        Button(role: .destructive) { confirm(row, .delete) } label: { Label(SimAction.delete.title, systemImage: SimAction.delete.icon).foregroundStyle(.red) }
                    }
                    .controlSize(.small).buttonStyle(.bordered).labelStyle(.titleAndIcon).padding(.vertical, 6)
                }
                Divider()
            }
            Button { showWindow(); model.cleanUpOpen = true } label: {
                let unused = model.unused
                Label(unused.isEmpty ? "Clean up…"
                                     : "Clean up \(unused.count) unused · frees \(Format.memory(unused.reduce(0) { $0 + ($1.footprint ?? 0) }))…",
                      systemImage: "power").labelStyle(.titleAndIcon).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).disabled(model.isStale)
            Toggle(isOn: Binding(get: { model.reapSettings.enabled }, set: { on in model.updateReapSettings { $0.enabled = on } })) {
                Text("Auto clean-up after \(Int(model.reapSettings.idlePeriod / 60)) min unused").frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.small)
            Divider()
            HStack {
                Button("Open Simanager") { showWindow() }
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit Simanager") { NSApp.terminate(nil) }
            }
        }
        .padding(14).frame(width: 520)
    }

    /// The row's state in a few words, with an icon so it is not told by colour alone.
    private func status(_ row: SimRow) -> some View {
        let kept = model.pinned.contains(row.id)
        let (text, icon, color): (String, String, Color) =
            row.hasLiveOwner ? ("In use", "circle.fill", .green)
            : model.isStale ? ("Owner unknown: a probe failed", "exclamationmark.triangle.fill", .orange)
            : kept ? ("Kept · never cleaned up automatically", "lock.fill", .gray)
            : ("Unused" + (model.cleanUpNote(row.id).map { " · " + $0 } ?? ""), "exclamationmark.triangle.fill", .orange)
        return HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 8)).foregroundStyle(color)
            Text(text)
        }
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The confirmation is the main window's sheet, so the menu bar cannot skip the evidence.
    private func confirm(_ row: SimRow, _ action: SimAction) {
        showWindow()
        model.confirmRequest = ConfirmRequest(row: row, action: action)
    }
}
