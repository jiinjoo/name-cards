import NameCardsCore
import SwiftUI

struct ScanView: View {
    @Bindable var model: ScanModel

    var body: some View {
        HSplitView {
            cameraPane
                .frame(minWidth: 480, minHeight: 360)
            CardTray(model: model)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Camera", selection: $model.selectedDeviceID) {
                    ForEach(model.devices) { device in
                        Text(device.isContinuity ? "\(device.name) (iPhone)" : device.name).tag(Optional(device.id))
                    }
                }
                .frame(width: 220)
                .help("Camera used for scanning")
            }
            ToolbarItem {
                TextField("Event, e.g. Tech Expo 2026", text: $model.eventName)
                    .frame(width: 220)
                    .help("Where you met these people. Used to group the contacts.")
            }
            ToolbarItem {
                Button("Capture Now", systemImage: "camera.shutter.button") { model.captureNow() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Capture immediately, even if no card outline is detected (⌘↩)")
            }
        }
        .task { await model.start() }
    }

    @ViewBuilder private var cameraPane: some View {
        switch model.cameraState {
        case .denied:
            ContentUnavailableView {
                Label("Camera access needed", systemImage: "video.slash")
            } description: {
                Text("Allow NameCards in System Settings › Privacy & Security › Camera, then reopen the app.")
            } actions: {
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            }
        case .noCamera:
            ContentUnavailableView("No camera found", systemImage: "video.slash",
                                   description: Text("Connect a camera, or bring your iPhone near this Mac to use it as a Continuity Camera."))
        case .failed(let message):
            ContentUnavailableView("Camera error", systemImage: "exclamationmark.triangle", description: Text(message))
        case .starting, .running:
            ZStack(alignment: .bottom) {
                CameraPreview(session: model.camera.session, quad: model.quad, color: outlineColor)
                Color.white.opacity(model.flash ? 0.6 : 0).allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.15), value: model.flash)
                statusPill.padding(16)
            }
        }
    }

    private var outlineColor: NSColor {
        switch model.decision {
        case .searching, .tracking: .systemYellow
        case .capture, .holding: .systemGreen
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            switch model.decision {
            case .searching:
                Image(systemName: "rectangle.dashed")
                Text("Hold a business card up to the camera")
            case .tracking(let progress):
                ProgressView(value: progress).progressViewStyle(.circular).controlSize(.small)
                Text("Hold still…")
            case .capture, .holding:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Captured. Take the card away and show the next one.")
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(alignment: .top) {
            if let notice = model.notice {
                Text(notice)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
                    .offset(y: -44)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: model.notice)
    }
}
