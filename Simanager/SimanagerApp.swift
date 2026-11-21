import SwiftUI
import SimanagerCore

@main struct SimanagerApp: App {
    /// Started here, not by the window: refreshing and reaping go on with the window closed.
    @State private var model: AppModel = {
        let model = AppModel()
        model.start()
        return model
    }()

    init() { Appearance.saved.apply() }

    var body: some Scene {
        Window("Simanager", id: "main") {
            SimTableView().environment(model)
        }
        // Opens as wide as the columns need (never wider than the screen), so nothing scrolls sideways or needs widening.
        .defaultSize(width: min(SimTableView.contentWidth, Double(NSScreen.main?.visibleFrame.width ?? 4000)), height: 900)

        // Closing the window leaves the app in the menu bar, which is what keeps auto-reaping alive.
        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            let high = (model.stats?.swapFraction ?? 0) > 0.8
            // The menu bar draws labels as templates and can drop the tint, so high swap also gets a mark.
            Text((high ? "⚠︎ " : "") + Format.gigabytes(model.shown?.totalFootprint ?? 0).split(separator: ".")[0] + " GB")
                .foregroundStyle(high ? .orange : .primary)
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView().environment(model) }
    }
}
