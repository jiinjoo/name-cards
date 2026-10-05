import CoreGraphics

/// OCR + parse for one cropped card, recovering cards held sideways or upside down.
public struct CardReader: Sendable {
    public struct Result: Sendable {
        /// The card image, rotated upright.
        public var image: CGImage
        public var lines: [OCRLine]
        public var draft: DraftContact
    }

    public var parser: CardParser
    private let recognizer = TextRecognizer()

    public init(parser: CardParser = CardParser()) {
        self.parser = parser
    }

    public func read(_ image: CGImage) async throws -> Result {
        var upright = image
        var lines = try await recognizer.recognize(image)

        // Vision only reads upright text. If little was read, or the crop is portrait (a landscape card held
        // sideways), score each rotation with a quick pass and redo the full read on the best one.
        if Self.quality(lines) < 40 || image.height > image.width {
            var best = (degrees: 0, score: Self.quality(try await recognizer.recognizeQuickly(image)))
            for degrees in [90, 270, 180] {
                guard let rotated = Self.rotate(image, degrees: degrees) else { continue }
                let score = Self.quality(try await recognizer.recognizeQuickly(rotated))
                if score > best.score * 1.2 { best = (degrees, score) }
            }
            if best.degrees != 0, let rotated = Self.rotate(image, degrees: best.degrees) {
                upright = rotated
                lines = try await recognizer.recognize(rotated)
            }
        }
        return Result(image: upright, lines: lines, draft: parser.parse(lines))
    }

    /// Confidence-weighted character count.
    static func quality(_ lines: [OCRLine]) -> Double {
        lines.reduce(0) { $0 + Double($1.confidence) * Double($1.text.count) }
    }

    /// Rotates clockwise by a multiple of 90°.
    public static func rotate(_ image: CGImage, degrees: Int) -> CGImage? {
        let quarterTurns = ((degrees / 90) % 4 + 4) % 4
        guard quarterTurns != 0 else { return image }
        let swapped = quarterTurns % 2 == 1
        let width = swapped ? image.height : image.width
        let height = swapped ? image.width : image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        // CoreGraphics' y axis points up, so a negative angle turns the image clockwise.
        context.rotate(by: -CGFloat(quarterTurns) * .pi / 2)
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return context.makeImage()
    }
}
