import Foundation

/// A contact extracted from a business card, awaiting user review.
public struct DraftContact: Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var givenName = ""
    public var familyName = ""
    public var phoneticGivenName = ""
    public var phoneticFamilyName = ""
    public var jobTitle = ""
    public var organization = ""
    public var phones: [String] = []
    public var emails: [String] = []
    public var urls: [String] = []
    public var address = ""
    /// Raw OCR lines, top-to-bottom, kept for reference and re-parsing.
    public var rawLines: [String] = []

    public init() {}

    public var displayName: String {
        [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
