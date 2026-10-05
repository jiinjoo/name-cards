import AppKit
import AVFoundation
import NameCardsCore
import Observation

@MainActor @Observable
final class ScanModel {
    enum CameraState: Equatable {
        case starting, running, noCamera, denied
        case failed(String)
    }

    var devices: [CameraDevice] = []
    var selectedDeviceID: String? {
        didSet {
            guard let id = selectedDeviceID, id != oldValue else { return }
            camera.use(deviceID: id)
            UserDefaults.standard.set(id, forKey: "cameraID")
        }
    }
    var cameraState = CameraState.starting
    var quad: Quad?
    var decision = CaptureGate.Decision.searching
    /// Briefly true after each capture, for the on-screen flash.
    var flash = false

    let camera = CameraController()
    let session: CardSession

    init(session: CardSession) {
        self.session = session
        camera.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDevices() }
            }
        }
    }

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { cameraState = .denied; return }
        default:
            cameraState = .denied
            return
        }
        refreshDevices()
        camera.start()
    }

    func refreshDevices() {
        devices = CameraController.availableDevices()
        if let current = selectedDeviceID, devices.contains(where: { $0.id == current }) {
            cameraState = .running
            return
        }
        let saved = UserDefaults.standard.string(forKey: "cameraID")
        // Prefer the last-used camera, then a Continuity Camera (iPhone), then anything.
        selectedDeviceID = devices.first(where: { $0.id == saved })?.id ?? devices.first?.id
        cameraState = selectedDeviceID == nil ? .noCamera : .running
    }

    func captureNow() {
        camera.captureNow()
    }

    private func handle(_ event: CameraEvent) {
        switch event {
        case let .frame(quad, decision):
            self.quad = quad
            self.decision = decision
        case let .captured(image):
            didCapture(image)
        case let .failed(message):
            cameraState = .failed(message)
        }
    }

    private func didCapture(_ image: CGImage) {
        NSSound(named: "Tink")?.play()
        flash = true
        Task { try? await Task.sleep(for: .milliseconds(150)); flash = false }
        session.add(image)
    }
}
