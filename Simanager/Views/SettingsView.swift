import SwiftUI
import SimanagerCore

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    static let key = "appearance"
    static var saved: Appearance { Appearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }

    /// Set on the app, so the window, the menu-bar popover, Settings and sheets all change together.
    /// `nil` hands the choice back to macOS: the app then follows the system setting, live.
    func apply() {
        NSApplication.shared.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Appearance.key) private var appearance = Appearance.system

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: appearance) { _, new in new.apply() }

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
