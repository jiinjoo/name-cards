import Foundation

/// One approved card on its way into Contacts: where it goes (new or merge) and which changes are ticked.
public struct SaveItem: Identifiable, Sendable {
    public enum Destination: Hashable, Sendable {
        case newContact
        case existing(ContactSnapshot)
    }

    public let id: UUID
    public var draft: DraftContact
    public var eventName: String
    /// Region for phone formatting and the address's country.
    public var region: String
    /// Existing contacts that may be this person, best first.
    public let candidates: [ContactMatch]
    public private(set) var destination: Destination
    public private(set) var plan: MergePlan
    /// IDs of ticked `FieldChange`s.
    public var selection: Set<String>

    /// Picks the best strong match as the destination, otherwise a new contact.
    public init(id: UUID, draft: DraftContact, eventName: String, region: String, contacts: [ContactSnapshot]) {
        self.id = id
        self.draft = draft
        self.eventName = eventName
        self.region = region
        candidates = ContactMatcher.matches(for: draft, in: contacts)
        if let best = candidates.first, best.score >= ContactMatcher.strongMatch {
            destination = .existing(best.contact)
        } else {
            destination = .newContact
        }
        plan = MergePlanner.plan(draft, into: destination.contact)
        selection = plan.defaultSelection
    }

    public mutating func setDestination(_ destination: Destination) {
        self.destination = destination
        plan = MergePlanner.plan(draft, into: destination.contact)
        selection = plan.defaultSelection
    }

    public var selectedChanges: [FieldChange] { plan.changes.filter { selection.contains($0.id) } }
}

extension SaveItem.Destination {
    public var contact: ContactSnapshot? {
        if case .existing(let contact) = self { return contact }
        return nil
    }
}
