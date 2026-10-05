import CoreGraphics

/// A detected card outline in Vision's normalised image space (0...1, origin bottom-left).
public struct Quad: Hashable, Sendable {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomRight: CGPoint
    public var bottomLeft: CGPoint

    public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// Largest distance any corner moved relative to `other`, in normalised units.
    public func maxCornerDistance(to other: Quad) -> CGFloat {
        zip(corners, other.corners).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
    }

    /// Converts to pixel coordinates of an image with the given size (still origin bottom-left).
    public func scaled(to size: CGSize) -> Quad {
        func scale(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
        return Quad(topLeft: scale(topLeft), topRight: scale(topRight),
                    bottomRight: scale(bottomRight), bottomLeft: scale(bottomLeft))
    }
}
