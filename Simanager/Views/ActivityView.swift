import SwiftUI

/// The last 100 things done, by you or by the app, with the reason for automatic ones.
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var expanded = false

    var body: some View {
        DisclosureGroup("Activity (\(model.activity.count))", isExpanded: $expanded) {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if model.activity.isEmpty { Text("Nothing yet.").foregroundStyle(.secondary) }
                    ForEach(model.activity) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.time.formatted(date: .abbreviated, time: .standard)).monospacedDigit().foregroundStyle(.secondary)
                            Text("\(entry.action) · \(entry.simulator)")
                            if entry.automatic { Text("automatic — \(entry.reason ?? "")").foregroundStyle(.secondary) }
                            if let error = entry.error { Text(error).foregroundStyle(.red) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 160)
        }
    }
}
