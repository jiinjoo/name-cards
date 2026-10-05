import Contacts
import Foundation
import Testing
@testable import NameCardsCore

func contact(_ id: String, given: String = "", family: String = "", org: String = "", title: String = "",
             emails: [String] = [], phones: [Phone] = [], addresses: [String] = []) -> ContactSnapshot {
    var c = ContactSnapshot(id: id)
    c.givenName = given
    c.familyName = family
    c.organization = org
    c.jobTitle = title
    c.emails = emails
    c.phones = phones
    c.addresses = addresses
    return c
}

func draft(given: String = "Jane", family: String = "Tan", org: String = "Acme Robotics Pte Ltd",
           title: String = "Senior Product Manager", emails: [String] = ["jane.tan@acme.sg"],
           phones: [Phone] = [Phone(number: "+6591234567", raw: "9123 4567", kind: .mobile)]) -> DraftContact {
    var d = DraftContact()
    d.givenName = given
    d.familyName = family
    d.organization = org
    d.jobTitle = title
    d.emails = emails
    d.phones = phones
    return d
}

@Suite struct ContactMatcherTests {
    @Test func sameEmailIsStrongMatch() {
        let matches = ContactMatcher.matches(for: draft(), in: [
            contact("1", given: "Jane", family: "Tan", emails: ["Jane.Tan@acme.sg"]),
            contact("2", given: "John", family: "Lee"),
        ])
        #expect(matches.map(\.id) == ["1"])
        #expect(matches[0].score >= ContactMatcher.strongMatch)
        #expect(matches[0].reasons.contains("Same email"))
    }

    @Test func sameMobileInDifferentFormatMatches() {
        let existing = contact("1", given: "J", family: "Tan", phones: [Phone(number: "9123 4567", raw: "", kind: .mobile)])
        let match = ContactMatcher.matches(for: draft(emails: []), in: [existing]).first
        #expect(match?.reasons.contains("Same mobile number") == true)
        #expect((match?.score ?? 0) >= ContactMatcher.strongMatch)
    }

    @Test func nameAndCompanyMatchIgnoringOrderAndSuffix() {
        let existing = contact("1", given: "Tan", family: "Jane", org: "ACME ROBOTICS")
        let match = ContactMatcher.matches(for: draft(emails: [], phones: []), in: [existing]).first
        #expect((match?.score ?? 0) >= ContactMatcher.strongMatch)
    }

    @Test func sameNameDifferentCompanyIsOnlyACandidate() {
        let existing = contact("1", given: "Jane", family: "Tan", org: "Globex")
        let match = ContactMatcher.matches(for: draft(emails: [], phones: []), in: [existing]).first
        #expect(match != nil)
        #expect((match?.score ?? 1) < ContactMatcher.strongMatch)
    }

    @Test func colleagueSharingOfficeLineIsNotMatched() {
        let office = Phone(number: "+6561234567", raw: "", kind: .work)
        let colleague = contact("1", given: "Wei Ming", family: "Lim", org: "Acme Robotics", phones: [office])
        #expect(ContactMatcher.matches(for: draft(emails: [], phones: [office]), in: [colleague]).isEmpty)
    }

    @Test func cjkCardMatchesLatinContactViaPhoneticName() {
        var card = draft(given: "美玲", family: "陈", org: "", emails: [], phones: [])
        card.phoneticGivenName = "Mei Ling"
        card.phoneticFamilyName = "Tan"
        let existing = contact("1", given: "Mei Ling", family: "Tan")
        #expect(ContactMatcher.matches(for: card, in: [existing]).first?.reasons.contains("Same name") == true)
    }
}

@Suite struct MergePlannerTests {
    @Test func newContactAddsEverythingPreTicked() {
        var card = draft()
        card.address = "1 Raffles Place\nSingapore 048616"
        let plan = MergePlanner.plan(card, into: nil)
        #expect(plan.changes.allSatisfy { $0.kind == .add })
        #expect(plan.changes.map(\.label) == ["Name", "Job title", "Company", "Mobile", "Email", "Address"])
        #expect(plan.defaultSelection.count == plan.changes.count)
    }

    @Test func mergeAddsNewDetailsAndProposesUntickedReplacements() {
        let existing = contact("1", given: "Jane", family: "Tan", org: "Acme Robotics", title: "Product Manager",
                               emails: ["jane@old.com"], phones: [Phone(number: "+65 9123 4567", raw: "", kind: .mobile)])
        let plan = MergePlanner.plan(draft(), into: existing)
        let byLabel = Dictionary(plan.changes.map { ($0.label, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(byLabel["Email"]?.kind == .add)
        #expect(byLabel["Job title"]?.kind == .replace(old: "Product Manager"))
        #expect(byLabel["Company"]?.kind == .replace(old: "Acme Robotics"))
        #expect(byLabel["Mobile"] == nil)
        #expect(plan.unchanged.contains("Name"))
        #expect(plan.unchanged.contains("Mobile"))
        // Replacements are never pre-ticked.
        #expect(plan.defaultSelection == ["email:jane.tan@acme.sg"])
    }

    @Test func identicalCardChangesNothing() {
        var existing = contact("1", given: "Jane", family: "Tan", org: "Acme Robotics Pte Ltd",
                               title: "Senior Product Manager", emails: ["jane.tan@acme.sg"],
                               phones: [Phone(number: "+6591234567", raw: "", kind: .mobile)])
        existing.addresses = ["1 Raffles Place\nSingapore 048616"]
        var card = draft()
        card.address = "1 Raffles Place\nSingapore 048616"
        #expect(MergePlanner.plan(card, into: existing).changes.isEmpty)
    }

    @Test func urlsComparedWithoutSchemeOrWww() {
        var card = draft()
        card.urls = ["www.acme.sg"]
        var existing = contact("1", given: "Jane", family: "Tan")
        existing.urls = ["https://acme.sg/"]
        #expect(!MergePlanner.plan(card, into: existing).changes.contains { $0.label == "Website" })
    }
}

@Suite struct SaveItemTests {
    @Test func strongMatchBecomesDefaultDestination() {
        let existing = contact("1", given: "Jane", family: "Tan", emails: ["jane.tan@acme.sg"])
        let item = SaveItem(id: UUID(), draft: draft(), eventName: "Expo", region: "SG", contacts: [existing])
        #expect(item.destination == .existing(existing))
        #expect(!item.selectedChanges.contains { $0.label == "Email" })
    }

    @Test func weakMatchDefaultsToNewContactButIsOffered() {
        let existing = contact("1", given: "Jane", family: "Tan", org: "Globex")
        var item = SaveItem(id: UUID(), draft: draft(emails: [], phones: []), eventName: "", region: "SG", contacts: [existing])
        #expect(item.destination == .newContact)
        #expect(item.candidates.map(\.id) == ["1"])
        item.setDestination(.existing(existing))
        #expect(item.plan.changes.contains { $0.label == "Company" && $0.kind == .replace(old: "Globex") })
        #expect(!item.selection.contains { $0.contains("organization") })
    }
}

@Suite struct ContactMapperTests {
    @Test func appliesSelectedChangesWithoutRemovingAnything() {
        let existing = CNMutableContact()
        existing.givenName = "Jane"
        existing.familyName = "Tan"
        existing.jobTitle = "Product Manager"
        existing.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: "jane@home.com" as NSString)]

        var card = draft()
        card.address = "1 Raffles Place\nSingapore 048616"
        let plan = MergePlanner.plan(card, into: ContactMapper.snapshot(of: existing))
        // Tick everything except the job title replacement.
        let changes = plan.changes.filter { $0.label != "Job title" }
        ContactMapper.apply(changes, from: card, to: existing, region: "SG")

        #expect(existing.jobTitle == "Product Manager")
        #expect(existing.organizationName == "Acme Robotics Pte Ltd")
        #expect(existing.emailAddresses.map { $0.value as String } == ["jane@home.com", "jane.tan@acme.sg"])
        #expect(existing.phoneNumbers.first?.label == CNLabelPhoneNumberMobile)
        #expect(existing.phoneNumbers.first?.value.stringValue == "+6591234567")
        #expect(existing.postalAddresses.first?.value.street == "1 Raffles Place\nSingapore 048616")
        #expect(existing.postalAddresses.first?.value.isoCountryCode == "sg")
    }

    @Test func companyOnlyCardBecomesOrganisationContact() {
        let new = CNMutableContact()
        let card = draft(given: "", family: "", org: "Acme", emails: ["info@acme.sg"], phones: [])
        ContactMapper.apply(MergePlanner.plan(card, into: nil).changes, from: card, to: new, region: "SG")
        #expect(new.contactType == .organization)
    }

    @Test func snapshotReadsLabelsAndAddresses() {
        let c = CNMutableContact()
        c.givenName = "Jane"
        c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberWorkFax, value: CNPhoneNumber(stringValue: "6123 4568"))]
        let address = CNMutablePostalAddress()
        address.street = "1 Raffles Place"
        address.city = "Singapore"
        c.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: address)]
        let snapshot = ContactMapper.snapshot(of: c)
        #expect(snapshot.phones.first?.kind == .fax)
        #expect(snapshot.addresses.first?.contains("1 Raffles Place") == true)
    }
}
