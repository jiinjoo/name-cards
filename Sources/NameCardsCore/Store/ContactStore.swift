import Contacts
import Foundation

public struct SaveOutcome: Sendable {
    public var contactID: String
    public var created: Bool
    /// Non-fatal problem, e.g. the contact couldn't be added to the event group.
    public var warning: String?
}

/// Where new contacts are written.
public struct ContactsAccount: Sendable, Equatable {
    public var containerID: String
    public var name: String
    public var isICloud: Bool
}

/// Contacts database access. Tests use a fake conforming type and never touch the real database.
public protocol ContactStoring: Sendable {
    func account() async throws -> ContactsAccount
    func fetchContacts() async throws -> [ContactSnapshot]
    func save(_ item: SaveItem, photo: Data?, addToEventGroup: Bool) async throws -> SaveOutcome
}

/// The real Contacts database. Calls block, so they run on a private queue (not Swift concurrency's threads).
public final class ContactStore: ContactStoring, @unchecked Sendable {
    private let store = CNContactStore()
    private let queue = DispatchQueue(label: "namecards.contacts", qos: .userInitiated)
    /// Event groups already found or created, by name. Accessed only on `queue`.
    private var groups: [String: CNGroup] = [:]

    public init() {}

    public static var isAuthorized: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    public static var isDenied: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        return status == .denied || status == .restricted
    }

    public func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    public func account() async throws -> ContactsAccount {
        try await onQueue { try self.targetAccount() }
    }

    public func fetchContacts() async throws -> [ContactSnapshot] {
        try await onQueue {
            var snapshots: [ContactSnapshot] = []
            let request = CNContactFetchRequest(keysToFetch: ContactMapper.keysToFetch)
            try self.store.enumerateContacts(with: request) { contact, _ in
                snapshots.append(ContactMapper.snapshot(of: contact))
            }
            return snapshots
        }
    }

    public func save(_ item: SaveItem, photo: Data?, addToEventGroup: Bool) async throws -> SaveOutcome {
        try await onQueue {
            let account = try self.targetAccount()
            let contact: CNMutableContact
            let created: Bool
            switch item.destination {
            case .newContact:
                contact = CNMutableContact()
                created = true
            case .existing(let snapshot):
                let keys = ContactMapper.keysToFetch + [CNContactImageDataKey as CNKeyDescriptor]
                let existing = try self.store.unifiedContact(withIdentifier: snapshot.id, keysToFetch: keys)
                contact = existing.mutableCopy() as! CNMutableContact
                created = false
            }
            ContactMapper.apply(item.selectedChanges, from: item.draft, to: contact, region: item.region)
            if let photo, created || !contact.imageDataAvailable {
                contact.imageData = photo
            }

            let request = CNSaveRequest()
            if created {
                request.add(contact, toContainerWithIdentifier: account.containerID)
            } else {
                request.update(contact)
            }
            try self.store.execute(request)

            var warning: String?
            let groupName = item.eventName.trimmed
            if addToEventGroup && !groupName.isEmpty {
                do {
                    try self.add(contact, toGroupNamed: groupName, in: account.containerID)
                } catch {
                    warning = "Saved, but couldn't add to the “\(groupName)” group: \(error.localizedDescription)"
                }
            }
            return SaveOutcome(contactID: contact.identifier, created: created, warning: warning)
        }
    }

    // MARK: Private (on queue)

    /// The iCloud container if there is one, otherwise the default container.
    private func targetAccount() throws -> ContactsAccount {
        let containers = try store.containers(matching: nil)
        if let iCloud = containers.first(where: { $0.type == .cardDAV && $0.name.localizedCaseInsensitiveContains("icloud") }) {
            return ContactsAccount(containerID: iCloud.identifier, name: iCloud.name, isICloud: true)
        }
        let defaultID = store.defaultContainerIdentifier()
        let name = containers.first { $0.identifier == defaultID }?.name ?? "On My Mac"
        return ContactsAccount(containerID: defaultID, name: name, isICloud: false)
    }

    private func add(_ contact: CNContact, toGroupNamed name: String, in containerID: String) throws {
        let group = try group(named: name, in: containerID)
        let members = try store.unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: group.identifier),
                                                keysToFetch: [])
        guard !members.contains(where: { $0.identifier == contact.identifier }) else { return }
        let request = CNSaveRequest()
        request.addMember(contact, to: group)
        try store.execute(request)
    }

    private func group(named name: String, in containerID: String) throws -> CNGroup {
        if let cached = groups[name] { return cached }
        let existing = try store.groups(matching: CNGroup.predicateForGroupsInContainer(withIdentifier: containerID))
        if let match = existing.first(where: { $0.name == name }) {
            groups[name] = match
            return match
        }
        let group = CNMutableGroup()
        group.name = name
        let request = CNSaveRequest()
        request.add(group, toContainerWithIdentifier: containerID)
        try store.execute(request)
        groups[name] = group
        return group
    }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result(catching: work)) }
        }
    }
}
