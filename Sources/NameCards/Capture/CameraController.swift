import AVFoundation
import CoreImage
import NameCardsCore
import os

private let log = Logger(subsystem: "com.jiinjoo.namecards", category: "camera")

enum CameraEvent: Sendable {
    /// Per analysed frame: the detected card outline (Vision space) and what the capture gate decided.
    case frame(quad: Quad?, decision: CaptureGate.Decision)
    /// A flattened card image, from a full-resolution photo when possible.
    case captured(CGImage)
    case failed(String)
}

struct CameraDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isContinuity: Bool
}

/// Owns the AVCaptureSession. Frames are analysed on `videoQueue`; when the card is still, a full-resolution
/// photo is taken and the card is cropped from it (small card text needs more than video resolution).
final class CameraController: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    /// Set once before `start`; called on background queues.
    var onEvent: (@Sendable (CameraEvent) -> Void)?

    private let sessionQueue = DispatchQueue(label: "namecards.camera.session")
    private let videoQueue = DispatchQueue(label: "namecards.camera.video", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()

    // Accessed only on videoQueue.
    private var gate = CaptureGate()
    private let detector = CardDetector()
    private var lastAnalysis: TimeInterval = 0
    private var latestFrame: CIImage?
    private var latestQuad: Quad?
    /// Video-resolution crops to fall back on if a photo fails, keyed by photo settings ID.
    private var fallbacks: [Int64: CGImage] = [:]

    static func availableDevices() -> [CameraDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.continuityCamera, .builtInWideAngleCamera, .external], mediaType: .video,
            position: .unspecified)
        return discovery.devices
            .map { CameraDevice(id: $0.uniqueID, name: $0.localizedName, isContinuity: $0.deviceType == .continuityCamera) }
            .sorted { $0.isContinuity && !$1.isContinuity }
    }

    func use(deviceID: String) {
        sessionQueue.async { [self] in
            guard let device = AVCaptureDevice(uniqueID: deviceID) else {
                onEvent?(.failed("Camera not found"))
                return
            }
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            session.sessionPreset = .high
            session.inputs.forEach(session.removeInput)
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else { throw CameraError("Can't use \(device.localizedName)") }
                session.addInput(input)
            } catch {
                onEvent?(.failed(error.localizedDescription))
                return
            }
            if session.outputs.isEmpty {
                videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
                if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
                if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            }
            if let largest = device.activeFormat.supportedMaxPhotoDimensions.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                photoOutput.maxPhotoDimensions = largest
            }
            let photo = photoOutput.connection(with: .video)
            let format = device.activeFormat.formatDescription.dimensions
            log.notice("""
                Using \(device.localizedName, privacy: .public) (\(device.deviceType.rawValue, privacy: .public)), \
                video \(format.width)x\(format.height), photo connection \
                \(photo == nil ? "missing" : "enabled=\(photo!.isEnabled) active=\(photo!.isActive)", privacy: .public), \
                max photo \(self.photoOutput.maxPhotoDimensions.width)x\(self.photoOutput.maxPhotoDimensions.height)
                """)
            videoQueue.async { [self] in gate.reset() }
        }
    }

    func start() {
        sessionQueue.async { [self] in if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        sessionQueue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    /// Capture whatever is in view now: the detected card if there is one, otherwise the whole frame.
    func captureNow() {
        videoQueue.async { [self] in
            guard let frame = latestFrame else { return }
            let crop = latestQuad.flatMap { detector.crop(frame, to: $0) }
                ?? CardDetector.context.createCGImage(frame, from: frame.extent)
            gate.reset()
            if let crop { takePhoto(fallback: crop, wholeFrame: latestQuad == nil) }
        }
    }

    /// Takes a full-resolution photo to crop the card from, or uses the video-frame crop when a photo isn't
    /// possible. Called on videoQueue.
    ///
    /// `capturePhoto` raises an Objective-C exception (which Swift can't catch, so the app aborts) when the
    /// photo output has no enabled, active video connection. That happens, e.g., while macOS video effects
    /// reconfigure a Continuity Camera. So check first, and fall back rather than crash.
    private func takePhoto(fallback: CGImage, wholeFrame: Bool = false) {
        guard !wholeFrame, session.isRunning, session.outputs.contains(photoOutput),
              let connection = photoOutput.connection(with: .video), connection.isEnabled, connection.isActive
        else {
            if !wholeFrame { log.notice("Photo capture unavailable; using the video frame") }
            onEvent?(.captured(fallback))
            return
        }
        let settings = AVCapturePhotoSettings()
        let maximum = photoOutput.maxPhotoDimensions
        if maximum.width > 0 && maximum.height > 0 {
            settings.maxPhotoDimensions = maximum
        }
        fallbacks[settings.uniqueID] = fallback
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // ~12 analyses per second is plenty for tracking a hand-held card.
        let now = CACurrentMediaTime()
        guard now - lastAnalysis >= 0.08, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        lastAnalysis = now

        let frame = CIImage(cvPixelBuffer: pixelBuffer)
        let quad = detector.detect(in: frame)
        var sharpness = 0.0
        if let quad, let preview = detector.crop(frame, to: quad, maxDimension: 640) {
            sharpness = ImageMetrics.sharpness(of: preview)
        }
        latestFrame = frame
        latestQuad = quad
        let decision = gate.process(.init(quad: quad, sharpness: sharpness, time: now))
        onEvent?(.frame(quad: quad, decision: decision))
        if decision == .capture, let quad, let crop = detector.crop(frame, to: quad) {
            takePhoto(fallback: crop)
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let id = photo.resolvedSettings.uniqueID
        let data = error == nil ? photo.fileDataRepresentation() : nil
        videoQueue.async { [self] in
            let fallback = fallbacks.removeValue(forKey: id)
            var crop: CGImage?
            if let data, let image = CIImage(data: data, options: [.applyOrientationProperty: true]),
               let quad = detector.detect(in: image) {
                crop = detector.crop(image, to: quad, maxDimension: 2400)
            }
            if let image = crop ?? fallback { onEvent?(.captured(image)) }
        }
    }
}

struct CameraError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
