import SwiftUI
import SimanagerCore

struct ConfirmSheet: View {
    @Environment(AppModel.self) private var model
    let request: ConfirmRequest
    @State private var scanFailed = false

    private var row: SimRow { request.row }
    private var directLabels: [String] {
        row.live.compactMap { if case .direct(let pid, _, let session) = $0 { session?.label ?? "pid \(pid)" } else { nil } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.action == .delete ? "Delete this simulator?" : "Shut down this simulator?").font(.title3.bold())
                Text(row.device.name).fontWeight(.semibold)
                Text("\(row.device.runtime) · holding \(Format.memory(row.footprint)) · up \(Format.uptime(row.uptime))\(row.device.isTestClone ? " · test clone" : "")")
                    .font(.callout).foregroundStyle(.secondary)
            }

            // The evidence is shown before the action is offered.
            VStack(alignment: .leading, spacing: 0) {
                fact("What is using it") { StatusCell(model: model, row: row) }
                Divider()
                fact("Last Claude command") {
                    if model.isScanning {
                        ProgressView("Checking what recently used it…").controlSize(.small)
                    } else if scanFailed {
                        Text("Could not be checked; recent use by a session elsewhere is unknown.").foregroundStyle(.orange)
                    } else {
                        LastCommandCell(model: model, row: row)
                    }
                }
            }.panel(radius: 10)

            if let first = directLabels.first {
                Text("In use right now by \(first).").foregroundStyle(.red).bold()
            } else if !row.hasLiveOwner, !model.isStale {
                Text("A session working from another folder could still be using it; that cannot be seen from here.").foregroundStyle(.secondary)
            }
            StaleNotice(model: model)
            if request.action == .shutdown, row.device.runtime == "iOS 26.5" {
                Text("iOS 26.5 may not boot cleanly again after a shut down. Delete instead.").foregroundStyle(.orange)
            }
            Text(request.action == .delete ? "Deletes the device, the app installed on it and its data."
                                           : "Nothing on disk is lost. Whatever is running in it stops, and the next boot is a cold boot.")

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { model.confirmRequest = nil }.keyboardShortcut(.defaultAction)
                Button(role: .destructive) {
                    model.confirmRequest = nil
                    Task { await model.perform(request.action, udid: row.id, automatic: false, reason: nil) }
                } label: {
                    Label(request.action.title, systemImage: request.action.icon).labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(model.isScanning)
            }
        }
        .padding(20).frame(width: 560)
        .task {
            if model.historyScannedAt[row.id].map({ Date().timeIntervalSince($0) > 60 }) ?? true {
                scanFailed = !(await model.scanHistory(for: [row.id]))
            }
        }
    }

    private func fact(_ name: String, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(name).font(.callout.weight(.semibold)).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }.padding(10)
    }
}
