import Contacts

/// Converts between Contacts objects and NameCards' plain values. No store access, so it is unit-testable.
public enum ContactMapper {
    /// The key strings are immutable constants, so sharing the array is safe.
    nonisolated(unsafe) public static let keysToFetch: [CNKeyDescriptor] = [
        CNContactNamePrefixKey, CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey,
        CNContactNameSuffixKey, CNContactPhoneticGivenNameKey, CNContactPhoneticFamilyNameKey, CNContactNicknameKey,
        CNContactOrganizationNameKey, CNContactDepartmentNameKey, CNContactJobTitleKey, CNContactPhoneNumbersKey,
        CNContactEmailAddressesKey, CNContactUrlAddressesKey, CNContactPostalAddressesKey,
        CNContactImageDataAvailableKey, CNContactTypeKey,
    ] as [CNKeyDescriptor]

    public static func snapshot(of contact: CNContact) -> ContactSnapshot {
        var snapshot = ContactSnapshot(id: contact.identifier)
        snapshot.namePrefix = contact.namePrefix
        snapshot.givenName = contact.givenName
        snapshot.middleName = contact.middleName
        snapshot.familyName = contact.familyName
        snapshot.nameSuffix = contact.nameSuffix
        snapshot.phoneticGivenName = contact.phoneticGivenName
        snapshot.phoneticFamilyName = contact.phoneticFamilyName
        snapshot.nickname = contact.nickname
        snapshot.organization = contact.organizationName
        snapshot.department = contact.departmentName
        snapshot.jobTitle = contact.jobTitle
        snapshot.phones = contact.phoneNumbers.map {
            Phone(number: $0.value.stringValue, raw: $0.value.stringValue, kind: kind(forLabel: $0.label))
        }
        snapshot.emails = contact.emailAddresses.map { $0.value as String }
        snapshot.urls = contact.urlAddresses.map { $0.value as String }
        snapshot.addresses = contact.postalAddresses.map {
            CNPostalAddressFormatter.string(from: $0.value, style: .mailingAddress)
        }
        snapshot.hasImage = contact.imageDataAvailable
        return snapshot
    }

    /// Copies the selected changes from `draft` onto `contact`. Existing values are only overwritten by
    /// `.replace` changes the user ticked, and nothing is ever removed.
    public static func apply(_ changes: [FieldChange], from draft: DraftContact, to contact: CNMutableContact, region: String) {
        for change in changes {
            switch change.target {
            case .name:
                contact.namePrefix = draft.namePrefix
                contact.givenName = draft.givenName
                contact.middleName = ""
                contact.familyName = draft.familyName
                contact.nameSuffix = draft.nameSuffix
            case .phoneticName:
                contact.phoneticGivenName = draft.phoneticGivenName
                contact.phoneticFamilyName = draft.phoneticFamilyName
            case .nickname:
                contact.nickname = draft.nickname
            case .jobTitle:
                contact.jobTitle = draft.jobTitle
            case .department:
                contact.departmentName = draft.department
            case .organization:
                contact.organizationName = draft.organization
            case .phone(let phone):
                contact.phoneNumbers.append(CNLabeledValue(label: label(for: phone.kind),
                                                           value: CNPhoneNumber(stringValue: phone.number)))
            case .email(let email):
                contact.emailAddresses.append(CNLabeledValue(label: CNLabelWork, value: email as NSString))
            case .url(let url):
                contact.urlAddresses.append(CNLabeledValue(label: CNLabelWork, value: url as NSString))
            case .address(let text):
                let address = CNMutablePostalAddress()
                address.street = text
                address.isoCountryCode = region.lowercased()
                contact.postalAddresses.append(CNLabeledValue(label: CNLabelWork, value: address))
            }
        }
        // A card with only a company (no person's name) becomes a company contact.
        if contact.givenName.isEmpty && contact.familyName.isEmpty && !contact.organizationName.isEmpty {
            contact.contactType = .organization
        }
    }

    static func label(for kind: Phone.Kind) -> String {
        switch kind {
        case .mobile: CNLabelPhoneNumberMobile
        case .work: CNLabelWork
        case .fax: CNLabelPhoneNumberWorkFax
        case .main: CNLabelPhoneNumberMain
        case .other: CNLabelOther
        }
    }

    static func kind(forLabel label: String?) -> Phone.Kind {
        switch label {
        case CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone: .mobile
        case CNLabelWork: .work
        case CNLabelPhoneNumberWorkFax, CNLabelPhoneNumberHomeFax, CNLabelPhoneNumberOtherFax: .fax
        case CNLabelPhoneNumberMain: .main
        default: .other
        }
    }
}
