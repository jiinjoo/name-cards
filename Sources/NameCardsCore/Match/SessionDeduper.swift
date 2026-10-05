import Foundation

/// Spots a card scanned twice in the same session (e.g. shown to the camera again later).
///
/// Colleagues' cards share a layout, office number and company, so those alone never count as a duplicate.
public enum SessionDeduper {
    /// The earlier draft that `draft` duplicates, if any.
    public static func duplicate(of draft: DraftContact, in earlier: [DraftContact]) -> DraftContact? {
        earlier.first { isSamePerson(draft, $0) }
    }

    public static func isSamePerson(_ a: DraftContact, _ b: DraftContact) -> Bool {
        if !Set(a.emails.map(normalizedEmail)).isDisjoint(with: b.emails.map(normalizedEmail)) { return true }
        let mobilesA = Set(a.phones.filter { $0.kind == .mobile }.map(\.comparable))
        let mobilesB = Set(b.phones.filter { $0.kind == .mobile }.map(\.comparable))
        if !mobilesA.isDisjoint(with: mobilesB) { return true }
        let nameA = a.displayName.lowercased(), nameB = b.displayName.lowercased()
        return !nameA.isEmpty && nameA == nameB
            && a.organization.lowercased() == b.organization.lowercased()
    }

    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

extension Phone {
    /// Digits only, last 8 at most, so "+65 9123 4567" and "9123 4567" compare equal.
    public var comparable: String { String(number.filter(\.isASCIIDigit).suffix(8)) }
}
