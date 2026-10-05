import AppKit
import SwiftUI

/// Switches between scanning (camera on) and reviewing (camera off).
struct RootView: View {
    @Bindable var state: AppState

    var body: some View {
        Group {
            switch state.mode {
            case .scan: ScanView(model: state.scan, onOpenCard: state.open)
            case .review: ReviewView(model: state.review)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $state.mode) {
                    Text("Scan").tag(AppState.Mode.scan)
                    Text(pending > 0 ? "Review (\(pending))" : "Review").tag(AppState.Mode.review)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .help("Scan (⌘1) · Review (⌘2)")
            }
        }
        .onChange(of: pending, initial: true) {
            NSApp.dockTile.badgeLabel = pending > 0 ? "\(pending)" : nil
        }
    }

    private var pending: Int { state.session.pendingCount }
}
