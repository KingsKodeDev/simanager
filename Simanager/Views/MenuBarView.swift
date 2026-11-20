import SwiftUI
import SimanagerCore

/// The glance: every simulator in one compact line, with the same confirmations as the window.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let rows = model.shown?.rows ?? []
            if rows.isEmpty { Text("No booted simulators").foregroundStyle(.secondary) }
            ForEach(rows) { row in
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill").font(.system(size: 7))
                        .foregroundStyle(row.hasLiveOwner ? .green : model.isStale ? .orange : .gray)
                        .help(row.hasLiveOwner ? "A live session is tied to it" : model.isStale ? "Owner unknown — a probe failed" : "No live owner")
                    Text(row.device.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(Format.memory(row.footprint)).monospacedDigit().foregroundStyle(.secondary)
                    Button("Shut down") { confirm(row, .shutdown) }
                    Button("Delete") { confirm(row, .delete) }
                }.controlSize(.small)
            }
            Divider()
            Toggle("Auto-reap after \(Int(model.reapSettings.idlePeriod / 60)) min without an owner",
                   isOn: Binding(get: { model.reapSettings.enabled }, set: { on in model.updateReapSettings { $0.enabled = on } }))
            HStack {
                Button("Open Simanager") { showWindow() }
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12).frame(width: 520)
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
