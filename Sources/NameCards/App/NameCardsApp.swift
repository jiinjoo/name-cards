import SwiftUI

@main
struct NameCardsApp: App {
    @State private var session: CardSession
    @State private var scanModel: ScanModel

    init() {
        let session = CardSession()
        _session = State(initialValue: session)
        _scanModel = State(initialValue: ScanModel(session: session))
    }

    var body: some Scene {
        Window("NameCards", id: "main") {
            RootView(session: session, scanModel: scanModel)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
    }
}
