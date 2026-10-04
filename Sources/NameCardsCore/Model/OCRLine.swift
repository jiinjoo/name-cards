import CoreGraphics

/// One line of recognised text. `box` is in Vision's normalised image space (origin bottom-left, 0...1).
public struct OCRLine: Hashable, Sendable {
    public var text: String
    public var box: CGRect
    public var confidence: Float

    public init(text: String, box: CGRect, confidence: Float = 1) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}
