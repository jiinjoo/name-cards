import SwiftUI

/// Switches between scanning (camera on) and reviewing (camera off).
struct RootView: View {
    enum Mode: Hashable { case scan, review }

    let session: CardSession
    let scanModel: ScanModel
    @State private var mode = Mode.scan

    var body: some View {
        Group {
            switch mode {
            case .scan: ScanView(model: scanModel)
            case .review: ReviewView(session: session)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $mode) {
                    Text("Scan").tag(Mode.scan)
                    Text(session.pendingCount > 0 ? "Review (\(session.pendingCount))" : "Review").tag(Mode.review)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
    }
}
