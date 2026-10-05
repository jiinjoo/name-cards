import CoreGraphics
import Foundation
import NameCardsCore
import Observation

/// All cards scanned in this session, persisted to disk so a crash or quit mid-event loses nothing.
@MainActor @Observable
final class CardSession {
    struct Card: Identifiable {
        var record: CardRecord
        var image: CGImage?
        var id: UUID { record.id }
    }

    /// Oldest first (scan order).
    private(set) var cards: [Card] = []
    var eventName = UserDefaults.standard.string(forKey: "eventName") ?? "" {
        didSet { UserDefaults.standard.set(eventName, forKey: "eventName") }
    }
    /// Short status message, e.g. a duplicate that was skipped.
    private(set) var notice: String?
    /// Default region for phone numbers on cards that don't reveal their country.
    let region: String

    private let store = SessionStore.standard
    private let processor: CardProcessor
    private var saveTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    init() {
        region = UserDefaults.standard.string(forKey: "defaultRegion") ?? Locale.current.region?.identifier ?? "US"
        processor = CardProcessor(region: region)
        restore()
    }

    var pendingCount: Int { cards.filter { $0.record.review == .pending && $0.record.status != .reading }.count }

    func card(_ id: UUID) -> Card? { cards.first { $0.id == id } }

    /// Region for parsing edits on this card: the card's own country if it reveals one.
    func region(for id: UUID) -> String {
        card(id)?.record.draft.flatMap { CardParser.inferRegion(from: $0.rawLines) } ?? region
    }

    // MARK: Capturing

    func add(_ image: CGImage) {
        let record = CardRecord(eventName: eventName)
        cards.append(Card(record: record, image: image))
        scheduleSave()
        let url = store.imageURL(for: record)
        Task {
            // Keep the raw capture on disk first, so an interrupted read can be retried on next launch.
            await Task.detached { CardProcessor.save(image, to: url) }.value
            await read(record.id, image: image)
        }
    }

    func retry(_ id: UUID) {
        guard let index = index(of: id), let image = cards[index].image else { return }
        cards[index].record.status = .reading
        Task { await read(id, image: image) }
    }

    private func read(_ id: UUID, image: CGImage) async {
        do {
            let result = try await processor.read(image)
            guard let index = index(of: id) else { return }
            let earlier = cards.filter { $0.id != id && $0.record.status == .ready }.compactMap(\.record.draft)
            if let original = SessionDeduper.duplicate(of: result.draft, in: earlier) {
                remove(id)
                show(notice: "Already scanned \(original.displayName.isEmpty ? "this card" : original.displayName) — skipped")
                return
            }
            cards[index].image = result.image
            cards[index].record.draft = result.draft
            cards[index].record.status = .ready
            let url = store.imageURL(for: cards[index].record)
            let upright = result.image
            Task.detached { CardProcessor.save(upright, to: url) }
        } catch {
            if let index = index(of: id) { cards[index].record.status = .failed(error.localizedDescription) }
        }
        scheduleSave()
    }

    // MARK: Reviewing

    func updateDraft(_ id: UUID, _ draft: DraftContact) {
        guard let index = index(of: id) else { return }
        cards[index].record.draft = draft
        scheduleSave()
    }

    func setReview(_ id: UUID, _ review: CardRecord.Review) {
        guard let index = index(of: id) else { return }
        cards[index].record.review = review
        scheduleSave()
    }

    func remove(_ id: UUID) {
        guard let index = index(of: id) else { return }
        let record = cards.remove(at: index).record
        try? FileManager.default.removeItem(at: store.imageURL(for: record))
        scheduleSave()
    }

    // MARK: Persistence

    private func restore() {
        let records = (try? store.load()) ?? []
        cards = records.map { Card(record: $0, image: CardProcessor.loadImage(at: store.imageURL(for: $0))) }
        for card in cards where card.record.status == .reading {
            if let image = card.image {
                Task { await read(card.id, image: image) }
            } else if let index = index(of: card.id) {
                cards[index].record.status = .failed("The card image was lost before it could be read.")
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let records = cards.map(\.record)
            let store = store
            await Task.detached { try? store.save(records) }.value
        }
    }

    private func index(of id: UUID) -> Int? { cards.firstIndex { $0.id == id } }

    private func show(notice: String) {
        self.notice = notice
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self.notice = nil }
        }
    }
}
