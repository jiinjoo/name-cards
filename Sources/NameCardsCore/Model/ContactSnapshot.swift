/// A plain-value copy of an existing contact, so matching and merge planning stay testable without Contacts.
public struct ContactSnapshot: Identifiable, Hashable, Sendable {
    public var id: String
    public var namePrefix = ""
    public var givenName = ""
    public var middleName = ""
    public var familyName = ""
    public var nameSuffix = ""
    public var phoneticGivenName = ""
    public var phoneticFamilyName = ""
    public var nickname = ""
    public var organization = ""
    public var department = ""
    public var jobTitle = ""
    public var phones: [Phone] = []
    public var emails: [String] = []
    public var urls: [String] = []
    /// Formatted postal addresses, one line per address line.
    public var addresses: [String] = []
    public var hasImage = false

    public init(id: String) {
        self.id = id
    }

    public var displayName: String {
        let name = [givenName, middleName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? organization : name
    }
}
