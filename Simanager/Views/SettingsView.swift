import SwiftUI
import SimanagerCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Toggle("Shut down or delete simulators nothing is using",
                   isOn: Binding(get: { model.reapSettings.enabled }, set: { on in model.updateReapSettings { $0.enabled = on } }))
            Picker("After", selection: Binding(get: { model.reapSettings.idlePeriod }, set: { v in model.updateReapSettings { $0.idlePeriod = v } })) {
                ForEach(ReapSettings.idlePeriods, id: \.self) { period in
                    Text(period < 3600 ? "\(Int(period / 60)) min" : "\(Int(period / 3600)) h").tag(period)
                }
            }.disabled(!model.reapSettings.enabled)
            Picker("Action", selection: Binding(get: { model.reapSettings.action }, set: { v in model.updateReapSettings { $0.action = v } })) {
                ForEach(SimAction.allCases) { Text($0.title).tag($0) }
            }.disabled(!model.reapSettings.enabled)
            Text("A simulator is reaped when it is not pinned, no live session has been tied to it for the whole period, and no running Claude session ran a command against it in that time. Works only while Simanager is running.")
                .font(.callout).foregroundStyle(.secondary)

            Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            if let error = model.launchAtLoginError { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped).frame(width: 460)
    }
}
