import AppKit
import AVFoundation
import NameCardsCore
import Observation

struct ScannedCard: Identifiable {
    enum Status: Equatable {
        case reading
        case ready
        case failed(String)
    }

    let id = UUID()
    let capturedAt = Date()
    var image: CGImage
    var imageURL: URL?
    var draft: DraftContact?
    var status = Status.reading
}

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
    var cards: [ScannedCard] = []
    var eventName = UserDefaults.standard.string(forKey: "eventName") ?? "" {
        didSet { UserDefaults.standard.set(eventName, forKey: "eventName") }
    }
    /// Briefly true after each capture, for the on-screen flash.
    var flash = false
    /// Short status message, e.g. a duplicate that was skipped.
    var notice: String?

    let camera = CameraController()
    private let processor: CardProcessor
    private var noticeTask: Task<Void, Never>?

    init() {
        let region = UserDefaults.standard.string(forKey: "defaultRegion") ?? Locale.current.region?.identifier ?? "US"
        processor = CardProcessor(region: region)
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

    func remove(_ card: ScannedCard) {
        cards.removeAll { $0.id == card.id }
        if let url = card.imageURL { try? FileManager.default.removeItem(at: url) }
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

        let card = ScannedCard(image: image)
        cards.insert(card, at: 0)
        Task {
            do {
                let (result, url) = try await processor.read(image, id: card.id)
                guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
                let earlier = cards.filter { $0.id != card.id && $0.status == .ready }.compactMap(\.draft)
                if let original = SessionDeduper.duplicate(of: result.draft, in: earlier) {
                    let name = original.displayName.isEmpty ? "this card" : original.displayName
                    cards.remove(at: index)
                    if let url { try? FileManager.default.removeItem(at: url) }
                    show(notice: "Already scanned \(name) — skipped")
                    return
                }
                cards[index].image = result.image
                cards[index].imageURL = url
                cards[index].draft = result.draft
                cards[index].status = .ready
            } catch {
                if let index = cards.firstIndex(where: { $0.id == card.id }) {
                    cards[index].status = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func show(notice: String) {
        self.notice = notice
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self.notice = nil }
        }
    }
}
