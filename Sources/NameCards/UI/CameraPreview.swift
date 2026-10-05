import AVFoundation
import NameCardsCore
import SwiftUI

/// Live camera feed with the detected card outline drawn on top.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let quad: Quad?
    let color: NSColor

    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.show(quad, color: color)
    }

    final class PreviewView: NSView {
        private let previewLayer = AVCaptureVideoPreviewLayer()
        private let outline = CAShapeLayer()

        init(session: AVCaptureSession) {
            super.init(frame: .zero)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspect
            outline.fillColor = nil
            outline.lineWidth = 4
            outline.lineJoin = .round
            layer?.addSublayer(previewLayer)
            // A sublayer of the preview shares its coordinate space, so converted points line up.
            previewLayer.addSublayer(outline)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            outline.frame = previewLayer.bounds
            CATransaction.commit()
        }

        func show(_ quad: Quad?, color: NSColor) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            guard let quad else {
                outline.path = nil
                return
            }
            // Vision's origin is bottom-left; capture-device points have their origin top-left.
            let points = quad.corners.map {
                previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: $0.x, y: 1 - $0.y))
            }
            let path = CGMutablePath()
            path.addLines(between: points)
            path.closeSubpath()
            outline.path = path
            outline.strokeColor = color.cgColor
        }
    }
}
