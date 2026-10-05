import Foundation

/// One proposed change to a contact. Values are applied from the draft, so a change only identifies what to copy.
public struct FieldChange: Identifiable, Hashable, Sendable {
    public enum Target: Hashable, Sendable {
        case name, phoneticName, nickname, jobTitle, department, organization
        case phone(Phone), email(String), url(String), address(String)
    }

    public enum Kind: Hashable, Sendable {
        /// Fills an empty field or adds another phone/email/URL/address.
        case add
        /// Overwrites an existing, different value.
        case replace(old: String)
    }

    public var target: Target
    public var kind: Kind
    /// Additions are pre-ticked; replacements need an explicit tick.
    public var selectedByDefault: Bool { kind == .add }
    /// Short field name for display, e.g. "Mobile", "Job title".
    public var label: String
    /// The new value as it will appear.
    public var value: String

    public var id: String {
        switch target {
        case .phone(let phone): "phone:\(phone.number)"
        case .email(let email): "email:\(email)"
        case .url(let url): "url:\(url)"
        case .address(let address): "address:\(address)"
        default: "\(target)"
        }
    }
}

public struct MergePlan: Hashable, Sendable {
    public var changes: [FieldChange]
    /// Fields the card and contact already agree on, for display.
    public var unchanged: [String]

    public var defaultSelection: Set<String> { Set(changes.filter(\.selectedByDefault).map(\.id)) }
}

/// Works out what a scanned card would add to or change in a contact. Never removes anything.
public enum MergePlanner {
    public static func plan(_ draft: DraftContact, into existing: ContactSnapshot?) -> MergePlan {
        var changes: [FieldChange] = []
        var unchanged: [String] = []
        let contact = existing ?? ContactSnapshot(id: "")

        func single(_ target: FieldChange.Target, _ label: String, new: String, old: String) {
            guard !new.trimmed.isEmpty else { return }
            if old.trimmed.isEmpty {
                changes.append(FieldChange(target: target, kind: .add, label: label, value: new))
            } else if TextSimilarity.normalized(old) == TextSimilarity.normalized(new) {
                unchanged.append(label)
            } else {
                changes.append(FieldChange(target: target, kind: .replace(old: old), label: label, value: new))
            }
        }

        // Name: same if equal in either order (Tan Mei Ling vs Mei Ling Tan).
        let newName = [draft.givenName, draft.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let oldName = [contact.givenName, contact.middleName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let newKeys = Set(TextSimilarity.nameKeys(given: draft.givenName, family: draft.familyName))
        let oldKeys = Set(TextSimilarity.nameKeys(given: contact.givenName + contact.middleName, family: contact.familyName))
        if !newName.isEmpty {
            if oldName.isEmpty {
                changes.append(FieldChange(target: .name, kind: .add, label: "Name", value: draftFullName(draft)))
            } else if !newKeys.isDisjoint(with: oldKeys) {
                unchanged.append("Name")
            } else {
                changes.append(FieldChange(target: .name, kind: .replace(old: oldName), label: "Name", value: draftFullName(draft)))
            }
        }
        single(.phoneticName, "Phonetic name",
               new: [draft.phoneticGivenName, draft.phoneticFamilyName].filter { !$0.isEmpty }.joined(separator: " "),
               old: [contact.phoneticGivenName, contact.phoneticFamilyName].filter { !$0.isEmpty }.joined(separator: " "))
        single(.nickname, "Nickname", new: draft.nickname, old: contact.nickname)
        single(.jobTitle, "Job title", new: draft.jobTitle, old: contact.jobTitle)
        single(.department, "Department", new: draft.department, old: contact.department)
        single(.organization, "Company", new: draft.organization, old: contact.organization)

        let existingPhones = Set(contact.phones.map(\.comparable))
        for phone in draft.phones where !phone.number.trimmed.isEmpty {
            if existingPhones.contains(phone.comparable) {
                unchanged.append(phone.kind.label)
            } else {
                changes.append(FieldChange(target: .phone(phone), kind: .add, label: phone.kind.label, value: phone.number))
            }
        }
        let existingEmails = Set(contact.emails.map { $0.lowercased() })
        for email in draft.emails where !email.trimmed.isEmpty {
            if existingEmails.contains(email.lowercased()) {
                unchanged.append("Email")
            } else {
                changes.append(FieldChange(target: .email(email), kind: .add, label: "Email", value: email))
            }
        }
        let existingURLs = Set(contact.urls.map(normalizedURL))
        for url in draft.urls where !url.trimmed.isEmpty {
            if existingURLs.contains(normalizedURL(url)) {
                unchanged.append("Website")
            } else {
                changes.append(FieldChange(target: .url(url), kind: .add, label: "Website", value: url))
            }
        }
        if !draft.address.trimmed.isEmpty {
            let new = TextSimilarity.normalized(draft.address)
            let known = contact.addresses.map(TextSimilarity.normalized).contains { old in
                old.contains(new) || new.contains(old) || TextSimilarity.jaroWinkler(old, new) >= 0.93
            }
            if known {
                unchanged.append("Address")
            } else {
                changes.append(FieldChange(target: .address(draft.address), kind: .add, label: "Address", value: draft.address))
            }
        }
        return MergePlan(changes: changes, unchanged: unchanged)
    }

    static func draftFullName(_ draft: DraftContact) -> String {
        [draft.namePrefix, draft.givenName, draft.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            + (draft.nameSuffix.isEmpty ? "" : ", " + draft.nameSuffix)
    }

    static func normalizedURL(_ url: String) -> String {
        var value = url.lowercased().trimmed
        for prefix in ["https://", "http://", "www."] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

extension Phone.Kind {
    public var label: String {
        switch self {
        case .mobile: "Mobile"
        case .work: "Work phone"
        case .fax: "Fax"
        case .main: "Main phone"
        case .other: "Phone"
        }
    }
}
