import Foundation
import Observation

/// Window-level navigation shared by the views and the menu commands.
@MainActor @Observable
final class AppState {
    enum Mode: Hashable { case scan, review }

    var mode = Mode.scan
    let session: CardSession
    let scan: ScanModel
    let review: ReviewModel

    init() {
        session = CardSession()
        scan = ScanModel(session: session)
        review = ReviewModel(session: session)
    }

    /// Jumps from the scan tray to a card in Review.
    func open(_ cardID: UUID) {
        review.reveal(cardID)
        mode = .review
    }
}
