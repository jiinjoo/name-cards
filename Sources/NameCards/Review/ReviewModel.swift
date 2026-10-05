import Foundation
import NameCardsCore
import Observation

/// Review list state and actions, shared by the Review views and the Card menu.
@MainActor @Observable
final class ReviewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case toReview = "To Review", approved = "Approved", saved = "Saved", skipped = "Skipped", all = "All"
        var id: Self { self }
    }

    let session: CardSession
    var filter = Filter.toReview {
        didSet { if oldValue != filter { selection = visibleCards.first?.id } }
    }
    var selection: UUID?
    /// Non-nil while the Save to Contacts sheet is open.
    var saving: SaveModel?

    init(session: CardSession) {
        self.session = session
    }

    var visibleCards: [CardSession.Card] {
        session.cards.filter { card in
            switch filter {
            case .toReview: card.record.review == .pending
            case .approved: card.record.review == .approved
            case .saved: card.record.review == .saved
            case .skipped: card.record.review == .skipped
            case .all: true
            }
        }
    }

    var selectedCard: CardSession.Card? { selection.flatMap(session.card) }

    /// Pending, readable cards that `approveAllClean` would approve.
    var cleanCards: [CardSession.Card] {
        session.cards.filter {
            $0.record.review == .pending && $0.record.status == .ready && $0.record.draft?.isReadyForQuickApproval == true
        }
    }

    var canApproveSelected: Bool {
        selectedCard.map { $0.record.status == .ready && $0.record.review != .saved } ?? false
    }

    var canSave: Bool { !session.approvedCards.isEmpty }

    // MARK: Actions

    func approve() {
        guard canApproveSelected, let id = selection else { return }
        session.setReview(id, .approved)
        advance(from: id)
    }

    func skip() {
        guard let card = selectedCard, card.record.review != .saved else { return }
        session.setReview(card.id, .skipped)
        advance(from: card.id)
    }

    func readAgain() {
        guard let id = selection else { return }
        session.retry(id)
    }

    func selectNext() { moveSelection(by: 1) }
    func selectPrevious() { moveSelection(by: -1) }

    @discardableResult
    func approveAllClean() -> Int {
        let ids = cleanCards.map(\.id)
        for id in ids { session.setReview(id, .approved) }
        if let selection, ids.contains(selection) { advance(from: selection) }
        return ids.count
    }

    func startSaving() {
        guard canSave else { return }
        saving = SaveModel(session: session)
    }

    /// Shows a specific card, switching filter if it isn't visible under the current one.
    func reveal(_ id: UUID) {
        if !visibleCards.contains(where: { $0.id == id }) { filter = .all }
        selection = id
    }

    func selectFirstIfNeeded() {
        if selectedCard == nil || !visibleCards.contains(where: { $0.id == selection }) {
            selection = visibleCards.first?.id
        }
    }

    private func moveSelection(by offset: Int) {
        let cards = visibleCards
        guard !cards.isEmpty else { return }
        let current = cards.firstIndex { $0.id == selection } ?? (offset > 0 ? -1 : cards.count)
        selection = cards[min(max(current + offset, 0), cards.count - 1)].id
    }

    /// After approving or skipping, move to the next card still waiting for review.
    private func advance(from id: UUID) {
        let pending = session.cards.filter { $0.record.review == .pending }
        let position = session.cards.firstIndex { $0.id == id } ?? 0
        let next = pending.first { card in (session.cards.firstIndex { $0.id == card.id } ?? 0) > position }
            ?? pending.first
        if filter == .toReview || next != nil { selection = next?.id }
    }
}
