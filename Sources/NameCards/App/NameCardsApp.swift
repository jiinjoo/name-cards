import SwiftUI

@main
struct NameCardsApp: App {
    @State private var state = AppState()

    var body: some Scene {
        Window("NameCards", id: "main") {
            RootView(state: state)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
        .commands { AppCommands(state: state) }

        Settings {
            SettingsView(session: state.session)
        }
    }
}
