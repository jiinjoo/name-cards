import Testing
@testable import NameCardsCore

@Test func displayNameJoinsNonEmptyParts() {
    var draft = DraftContact()
    draft.givenName = "Jane"
    #expect(draft.displayName == "Jane")
    draft.familyName = "Tan"
    #expect(draft.displayName == "Jane Tan")
}
