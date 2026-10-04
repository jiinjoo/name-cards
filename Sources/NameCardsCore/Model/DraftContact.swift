import Foundation

/// A contact extracted from a business card, awaiting user review.
public struct DraftContact: Identifiable, Hashable, Sendable {
    /// Fields the user reviews; each carries a parser confidence so the UI can highlight weak guesses.
    public enum Field: String, CaseIterable, Hashable, Sendable {
        case name, phoneticName, nickname, jobTitle, department, organization, phones, emails, urls, address
    }

    public var id = UUID()
    public var namePrefix = ""
    public var givenName = ""
    public var familyName = ""
    public var nameSuffix = ""
    public var phoneticGivenName = ""
    public var phoneticFamilyName = ""
    public var nickname = ""
    public var jobTitle = ""
    public var department = ""
    public var organization = ""
    public var phones: [Phone] = []
    public var emails: [String] = []
    public var urls: [String] = []
    /// Postal address as printed, one line per card line.
    public var address = ""
    /// Raw OCR lines, top to bottom, kept for reference and re-parsing.
    public var rawLines: [String] = []
    /// 0...1 per field; absent means the field was not found.
    public var confidence: [Field: Double] = [:]

    public init() {}

    public var displayName: String {
        [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    public func confidence(for field: Field) -> Double { confidence[field] ?? 0 }
}

public struct Phone: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Hashable, Sendable { case mobile, work, fax, main, other }

    /// E.164 (e.g. "+6591234567") when normalisation succeeded, otherwise the text as printed.
    public var number: String
    /// The text as it appeared on the card.
    public var raw: String
    public var kind: Kind

    public init(number: String, raw: String, kind: Kind) {
        self.number = number
        self.raw = raw
        self.kind = kind
    }

    public var isNormalized: Bool { number.hasPrefix("+") && number.dropFirst().allSatisfy(\.isNumber) }
}
