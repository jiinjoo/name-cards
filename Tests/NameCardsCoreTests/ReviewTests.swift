import Foundation
import Testing
@testable import NameCardsCore

@Suite struct DraftEditingTests {
    @Test func lowConfidenceAndMissingNameNeedAttention() {
        var draft = DraftContact()
        draft.organization = "Acme"
        draft.confidence = [.organization: 0.4, .emails: 0.95]
        #expect(draft.fieldsNeedingAttention == [.name, .organization])
        draft.markReviewed(.organization)
        draft.givenName = "Jane"
        #expect(draft.fieldsNeedingAttention.isEmpty)
    }

    @Test func assignNameSplitsAndClearsHighlight() {
        var draft = DraftContact()
        draft.confidence[.name] = 0.3
        draft.assign("Dr. Jane Tan", as: .name, region: "SG")
        #expect(draft.namePrefix == "Dr.")
        #expect(draft.givenName == "Jane")
        #expect(draft.familyName == "Tan")
        #expect(!draft.needsAttention(.name))
    }

    @Test func assignPhoneNormalisesAndUsesChosenKind() {
        var draft = DraftContact()
        draft.assign("Tel: 9123 4567", as: .mobile, region: "SG")
        #expect(draft.phones == [Phone(number: "+6591234567", raw: "9123 4567", kind: .mobile)])
        // Re-assigning the same number changes its kind rather than duplicating it.
        draft.assign("9123 4567", as: .fax, region: "SG")
        #expect(draft.phones.map(\.kind) == [.fax])
    }

    @Test func assignEmailExtractsAddressFromLabelledLine() {
        var draft = DraftContact()
        draft.assign("E: Jane.Tan@Acme.com", as: .email, region: "SG")
        draft.assign("jane.tan@acme.com", as: .email, region: "SG")
        #expect(draft.emails == ["jane.tan@acme.com"])
    }

    @Test func assignAddressAppendsLines() {
        var draft = DraftContact()
        draft.assign("1 Raffles Place", as: .address, region: "SG")
        draft.assign("Singapore 048616", as: .address, region: "SG")
        #expect(draft.address == "1 Raffles Place\nSingapore 048616")
    }
}

@Suite struct SessionStoreTests {
    @Test func roundTripsRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "namecards-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        #expect(try store.load().isEmpty)

        var draft = parse([("Jane Tan", 0.06), ("M +65 9123 4567", 0.04)])
        draft.confidence[.organization] = 0.3
        let records = [
            CardRecord(eventName: "Expo", draft: draft, status: .ready, review: .approved),
            CardRecord(status: .failed("Unreadable")),
            CardRecord(),
        ]
        try store.save(records)
        let loaded = try store.load()
        #expect(loaded.map(\.id) == records.map(\.id))
        #expect(loaded[0].draft == draft)
        #expect(loaded[0].review == .approved)
        #expect(loaded[1].status == .failed("Unreadable"))
        #expect(loaded[2].status == .reading)
        #expect(store.imageURL(for: loaded[0]).lastPathComponent == "\(records[0].id.uuidString).jpg")
    }
}
