import CoreImage
import Vision

/// Finds a business card in an image and produces a flattened, perspective-corrected crop of it.
public struct CardDetector: Sendable {
    /// Shared because CIContext is expensive to create; it is documented as thread-safe.
    nonisolated(unsafe) public static let context = CIContext(options: [.cacheIntermediates: false])

    /// Minimum card size as a fraction of the frame's shorter side.
    public var minimumSize: Float = 0.25

    public init() {}

    /// The most prominent card-shaped rectangle, or nil.
    public func detect(in image: CIImage) -> Quad? {
        let request = VNDetectRectanglesRequest()
        // Business cards are roughly 0.55–0.65 short/long side; allow for perspective.
        request.minimumAspectRatio = 0.4
        request.maximumAspectRatio = 0.85
        request.minimumSize = minimumSize
        request.quadratureTolerance = 25
        request.minimumConfidence = 0.6
        request.maximumObservations = 1
        do {
            try VNImageRequestHandler(ciImage: image).perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        return Quad(topLeft: observation.topLeft, topRight: observation.topRight,
                    bottomRight: observation.bottomRight, bottomLeft: observation.bottomLeft)
    }

    /// Perspective-corrects the quad's region of `image`. Output is landscape when the card is wider than tall
    /// as seen; portrait/rotated cards are handled later by `CardReader`.
    public func crop(_ image: CIImage, to quad: Quad, maxDimension: CGFloat? = nil) -> CGImage? {
        let pixels = quad.scaled(to: image.extent.size)
        func vector(_ p: CGPoint) -> CIVector { CIVector(x: p.x + image.extent.minX, y: p.y + image.extent.minY) }
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(vector(pixels.topLeft), forKey: "inputTopLeft")
        filter.setValue(vector(pixels.topRight), forKey: "inputTopRight")
        filter.setValue(vector(pixels.bottomRight), forKey: "inputBottomRight")
        filter.setValue(vector(pixels.bottomLeft), forKey: "inputBottomLeft")
        guard var output = filter.outputImage else { return nil }
        if let maxDimension {
            let scale = min(1, maxDimension / max(output.extent.width, output.extent.height))
            if scale < 1 { output = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
        }
        return Self.context.createCGImage(output, from: output.extent.integral)
    }
}
