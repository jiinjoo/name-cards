import Testing
@testable import NameCardsCore

@Suite struct PhoneNumbersTests {
    @Test(arguments: [
        ("+65 6123 4567", "SG", "+6561234567"),
        ("6123 4567", "SG", "+6561234567"),
        ("65 9123 4567", "SG", "+6591234567"),
        ("012-345 6789", "MY", "+60123456789"),
        ("+60 3-2161 1234", "SG", "+60321611234"),
        ("0065 6123 4567", "MY", "+6561234567"),
        ("+44 (0)20 7946 0018", "SG", "+442079460018"),
        ("(415) 555-0132", "US", "+14155550132"),
        ("138 0013 8000", "CN", "+8613800138000"),
        ("2345 6789", "HK", "+85223456789"),
    ])
    func normalize(raw: String, region: String, expected: String) {
        #expect(PhoneNumbers.normalize(raw, region: region) == expected)
    }

    @Test func unknownCountryIsLeftUnnormalised() {
        #expect(PhoneNumbers.normalize("03-2161 1234", region: "SG") == nil)
        #expect(PhoneNumbers.normalize("123", region: "SG") == nil)
    }

    @Test(arguments: [
        ("M: ", Phone.Kind.mobile), ("Tel ", .work), ("Fax:", .fax), ("H/P ", .mobile), ("传真：", .fax),
        ("携帯 ", .mobile), ("휴대폰 ", .mobile), ("Hotline: ", .main), ("Direct ", .work),
    ])
    func labels(text: String, kind: Phone.Kind) {
        #expect(PhoneNumbers.kind(forPrecedingText: text) == kind)
    }

    @Test func labelMustStartAtWordBoundary() {
        #expect(PhoneNumbers.kind(forPrecedingText: "Hotel ") == nil)
    }

    @Test func unlabelledKindInferredFromPrefix() {
        #expect(PhoneNumbers.inferredKind("+6591234567") == .mobile)
        #expect(PhoneNumbers.inferredKind("+6561234567") == .work)
        #expect(PhoneNumbers.inferredKind(nil) == .work)
    }

    @Test func japanesePostcodeIsNotAPhone() {
        #expect(PhoneNumbers.find(in: "〒150-0002 東京都", region: "JP").isEmpty)
    }

    @Test func shortNumbersAreIgnored() {
        #expect(PhoneNumbers.find(in: "Level 12, 048616", region: "SG").isEmpty)
    }
}
