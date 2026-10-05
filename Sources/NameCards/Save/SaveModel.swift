import Foundation
import NameCardsCore
import Observation

/// Drives the "Save to Contacts" sheet: permission, matching approved cards, then writing them.
@MainActor @Observable
final class SaveModel {
    enum Phase {
        case loading
        case denied
        case ready
        case saving(done: Int, total: Int)
        case finished(Summary)
        case failed(String)
    }

    struct Summary {
        var created = 0
        var updated = 0
        var warnings: [String] = []
        var failures: [String] = []
    }

    private(set) var phase = Phase.loading
    var items: [SaveItem] = []
    private(set) var account: ContactsAccount?
    var addToEventGroup = UserDefaults.standard.object(forKey: "addToEventGroup") as? Bool ?? true {
        didSet { UserDefaults.standard.set(addToEventGroup, forKey: "addToEventGroup") }
    }
    var useCardAsPhoto = UserDefaults.standard.bool(forKey: "useCardAsPhoto") {
        didSet { UserDefaults.standard.set(useCardAsPhoto, forKey: "useCardAsPhoto") }
    }

    let session: CardSession
    private let store = ContactStore()

    init(session: CardSession) {
        self.session = session
    }

    func load() async {
        phase = .loading
        do {
            if !ContactStore.isAuthorized {
                guard !ContactStore.isDenied, try await store.requestAccess() else {
                    phase = .denied
                    return
                }
            }
            account = try await store.account()
            let contacts = try await store.fetchContacts()
            items = session.approvedCards.compactMap { card in
                guard let draft = card.record.draft else { return nil }
                return SaveItem(id: card.id, draft: draft, eventName: card.record.eventName,
                                region: session.region(for: card.id), contacts: contacts)
            }
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    var mergeCount: Int { items.filter { $0.destination != .newContact }.count }

    func saveAll() async {
        var summary = Summary()
        let total = items.count
        for (index, item) in items.enumerated() {
            phase = .saving(done: index, total: total)
            let name = item.draft.reviewTitle
            let photo = useCardAsPhoto ? session.card(item.id)?.image.flatMap { CardProcessor.photoData(from: $0) } : nil
            do {
                let outcome = try await store.save(item, photo: photo, addToEventGroup: addToEventGroup)
                if outcome.created { summary.created += 1 } else { summary.updated += 1 }
                if let warning = outcome.warning { summary.warnings.append("\(name): \(warning)") }
                session.markSaved(item.id, contactIdentifier: outcome.contactID)
            } catch {
                summary.failures.append("\(name): \(error.localizedDescription)")
            }
        }
        phase = .finished(summary)
    }
}

extension SaveModel: Identifiable {}
