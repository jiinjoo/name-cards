import SwiftUI

@main
struct NameCardsApp: App {
    @State private var scanModel = ScanModel()

    var body: some Scene {
        Window("NameCards", id: "scan") {
            ScanView(model: scanModel)
                .frame(minWidth: 900, minHeight: 540)
        }
        .windowToolbarStyle(.unified)
    }
}
