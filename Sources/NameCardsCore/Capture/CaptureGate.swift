import Foundation

/// Decides when to auto-capture a card from a stream of per-frame detections.
///
/// A card is captured once its outline has stayed put for `stableDuration` and the frame is sharp enough
/// (or after `maxWait` regardless, so a slightly soft card still gets captured). After a capture the gate
/// holds until the card leaves the frame, or the outline jumps somewhere new (a card slid in to replace it).
/// If that jump was just the same card being nudged, `SessionDeduper` drops the repeat by content.
public struct CaptureGate: Sendable {
    public struct Config: Sendable {
        /// How long the outline must stay still before capturing.
        public var stableDuration: TimeInterval = 0.6
        /// Capture even if never sharp once the card has been still this long.
        public var maxWait: TimeInterval = 2.0
        /// Corner movement (normalised) that counts as the card moving.
        public var maxCornerDrift: CGFloat = 0.025
        /// Laplacian variance threshold; see `ImageMetrics.sharpness`.
        public var minSharpness: Double = 60
        /// Detection dropouts shorter than this are ignored (rectangle detection flickers).
        public var dropoutTolerance: TimeInterval = 0.3
        /// How long the card must be gone before the next card can be captured.
        public var absenceToRearm: TimeInterval = 0.5
        /// Outline movement (normalised) after a capture that counts as a different card.
        public var swapDistance: CGFloat = 0.08

        public init() {}
    }

    public struct Frame: Sendable {
        public var quad: Quad?
        public var sharpness: Double
        public var time: TimeInterval

        public init(quad: Quad?, sharpness: Double = 0, time: TimeInterval) {
            self.quad = quad
            self.sharpness = sharpness
            self.time = time
        }
    }

    public enum Decision: Equatable, Sendable {
        /// No card in view.
        case searching
        /// A card is in view and settling; `progress` runs 0...1 towards capture.
        case tracking(progress: Double)
        /// Capture this frame now.
        case capture
        /// Already captured the card in view; waiting for it to be removed.
        case holding
    }

    enum State: Equatable {
        case searching
        case tracking(anchor: Quad, since: TimeInterval, lastSeen: TimeInterval)
        case holding(captured: Quad, lastSeen: TimeInterval)
    }

    public var config: Config
    private(set) var state: State = .searching

    public init(config: Config = Config()) {
        self.config = config
    }

    public mutating func process(_ frame: Frame) -> Decision {
        switch state {
        case .searching:
            guard let quad = frame.quad else { return .searching }
            state = .tracking(anchor: quad, since: frame.time, lastSeen: frame.time)
            return .tracking(progress: 0)

        case let .tracking(anchor, since, lastSeen):
            guard let quad = frame.quad else {
                if frame.time - lastSeen > config.dropoutTolerance {
                    state = .searching
                    return .searching
                }
                return .tracking(progress: progress(since: since, now: frame.time))
            }
            if quad.maxCornerDistance(to: anchor) > config.maxCornerDrift {
                state = .tracking(anchor: quad, since: frame.time, lastSeen: frame.time)
                return .tracking(progress: 0)
            }
            let held = frame.time - since
            if (held >= config.stableDuration && frame.sharpness >= config.minSharpness) || held >= config.maxWait {
                state = .holding(captured: quad, lastSeen: frame.time)
                return .capture
            }
            state = .tracking(anchor: anchor, since: since, lastSeen: frame.time)
            return .tracking(progress: progress(since: since, now: frame.time))

        case let .holding(captured, lastSeen):
            guard let quad = frame.quad else {
                if frame.time - lastSeen >= config.absenceToRearm {
                    state = .searching
                    return .searching
                }
                return .holding
            }
            if quad.maxCornerDistance(to: captured) > config.swapDistance {
                state = .tracking(anchor: quad, since: frame.time, lastSeen: frame.time)
                return .tracking(progress: 0)
            }
            state = .holding(captured: captured, lastSeen: frame.time)
            return .holding
        }
    }

    /// Forget any held card, e.g. after a manual capture or camera switch.
    public mutating func reset() {
        state = .searching
    }

    private func progress(since: TimeInterval, now: TimeInterval) -> Double {
        min(1, (now - since) / config.stableDuration)
    }
}
