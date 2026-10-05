import Foundation

/// What an OCR line can be re-assigned to when the parser got it wrong ("Use this line as…").
public enum LineAssignment: String, CaseIterable, Identifiable, Sendable {
    case name, jobTitle, department, organization, mobile, workPhone, fax, email, website, address

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .name: "Name"
        case .jobTitle: "Job Title"
        case .department: "Department"
        case .organization: "Company"
        case .mobile: "Mobile"
        case .workPhone: "Work Phone"
        case .fax: "Fax"
        case .email: "Email"
        case .website: "Website"
        case .address: "Address (add line)"
        }
    }
}

extension DraftContact {
    /// Confidence below which a field is highlighted for the user to check.
    public static let reviewThreshold = 0.6

    /// Fields the user should look at: found with low confidence, or a missing name.
    public var fieldsNeedingAttention: [Field] {
        var fields = Field.allCases.filter { field in
            let value = confidence[field] ?? 0
            return value > 0 && value < Self.reviewThreshold
        }
        if givenName.isEmpty && familyName.isEmpty && !fields.contains(.name) {
            fields.insert(.name, at: 0)
        }
        return fields
    }

    public func needsAttention(_ field: Field) -> Bool {
        fieldsNeedingAttention.contains(field)
    }

    /// Records that the user has checked or typed a field, so it is no longer highlighted.
    public mutating func markReviewed(_ field: Field) {
        confidence[field] = 1
    }

    /// Applies an OCR line to a field, parsing it the way that field expects.
    public mutating func assign(_ line: String, as assignment: LineAssignment, region: String) {
        let text = line.trimmed
        guard !text.isEmpty else { return }
        switch assignment {
        case .name:
            let parts = NameSplitter.split(text, japaneseContext: rawLines.contains { $0.containsKana })
            namePrefix = parts.prefix
            givenName = parts.given
            familyName = parts.family
            nameSuffix = parts.suffix
            markReviewed(.name)
        case .jobTitle:
            jobTitle = text
            markReviewed(.jobTitle)
        case .department:
            department = text
            markReviewed(.department)
        case .organization:
            organization = text
            markReviewed(.organization)
        case .mobile, .workPhone, .fax:
            let kind: Phone.Kind = assignment == .mobile ? .mobile : assignment == .fax ? .fax : .work
            let found = PhoneNumbers.find(in: text, region: region).map(\.phone)
            let phone = found.first ?? Phone(number: PhoneNumbers.normalize(text, region: region) ?? text,
                                             raw: text, kind: kind)
            // The user's choice of kind wins over whatever label the line carried.
            let assigned = Phone(number: phone.number, raw: phone.raw, kind: kind)
            if let index = phones.firstIndex(where: { $0.number == assigned.number }) {
                phones[index] = assigned
            } else {
                phones.append(assigned)
            }
            markReviewed(.phones)
        case .email:
            let email = (text.range(of: #"[^\s:：]+@[^\s]+"#, options: .regularExpression).map { String(text[$0]) } ?? text)
                .lowercased()
            if !emails.contains(email) { emails.append(email) }
            markReviewed(.emails)
        case .website:
            let url = text.lowercased()
            if !urls.contains(url) { urls.append(url) }
            markReviewed(.urls)
        case .address:
            address = address.isEmpty ? text : address + "\n" + text
            markReviewed(.address)
        }
    }
}
