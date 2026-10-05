/// An existing contact that may be the same person as a scanned card.
public struct ContactMatch: Identifiable, Hashable, Sendable {
    public var contact: ContactSnapshot
    /// 0...1; at or above `ContactMatcher.strongMatch` the merge is proposed by default.
    public var score: Double
    /// Human-readable evidence, e.g. "Same email".
    public var reasons: [String]
    public var id: String { contact.id }
}

/// Finds existing contacts that look like the same person as a scanned card.
public enum ContactMatcher {
    public static let strongMatch = 0.85
    static let candidateThreshold = 0.6

    public static func matches(for draft: DraftContact, in contacts: [ContactSnapshot], limit: Int = 3) -> [ContactMatch] {
        let emails = Set(draft.emails.map { $0.lowercased() })
        let mobiles = Set(draft.phones.filter { $0.kind == .mobile }.map(\.comparable))
        let otherPhones = Set(draft.phones.filter { $0.kind != .mobile }.map(\.comparable))
        let draftNames = TextSimilarity.nameKeys(given: draft.givenName, family: draft.familyName,
                                                 others: [draft.phoneticGivenName + draft.phoneticFamilyName,
                                                          draft.phoneticFamilyName + draft.phoneticGivenName, draft.nickname])

        var results: [ContactMatch] = []
        for contact in contacts {
            var score = 0.0
            var reasons: [String] = []

            if contact.emails.contains(where: { emails.contains($0.lowercased()) }) {
                score = 1.0
                reasons.append("Same email")
            }
            let contactPhones = Set(contact.phones.map(\.comparable))
            let sharesMobile = !mobiles.isDisjoint(with: contactPhones)
            if sharesMobile {
                score = max(score, 0.95)
                reasons.append("Same mobile number")
            }

            let nameScore = nameSimilarity(draftNames, contact)
            let companyScore = TextSimilarity.companySimilarity(draft.organization, contact.organization)
            if nameScore >= 0.92 { reasons.append(nameScore == 1 ? "Same name" : "Similar name") }
            if companyScore >= 0.85 { reasons.append("Same company") }

            // A shared office line alone means a colleague, not the same person.
            if !sharesMobile, !otherPhones.isDisjoint(with: contactPhones) {
                reasons.append("Shares a phone number")
                if nameScore >= 0.85 { score = max(score, 0.9) }
            }
            if nameScore >= 0.92 {
                score = max(score, companyScore >= 0.85 ? 0.88 : 0.65)
            }

            if score >= candidateThreshold {
                results.append(ContactMatch(contact: contact, score: score, reasons: reasons))
            }
        }
        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }

    static func nameSimilarity(_ draftNames: [String], _ contact: ContactSnapshot) -> Double {
        let contactNames = TextSimilarity.nameKeys(
            given: [contact.givenName, contact.middleName].filter { !$0.isEmpty }.joined(separator: " "),
            family: contact.familyName,
            others: [contact.phoneticGivenName + contact.phoneticFamilyName,
                     contact.phoneticFamilyName + contact.phoneticGivenName, contact.nickname])
        var best = 0.0
        for a in draftNames where a.count >= 2 {
            for b in contactNames where b.count >= 2 {
                best = max(best, a == b ? 1 : TextSimilarity.jaroWinkler(a, b))
            }
        }
        return best
    }
}
