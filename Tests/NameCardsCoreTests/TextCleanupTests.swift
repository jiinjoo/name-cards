import Testing
@testable import NameCardsCore

@Suite struct TextCleanupTests {
    @Test(arguments: [
        ("Email: nagisa sugimura@nipponkayaku.co.jp", "Email: nagisa.sugimura@nipponkayaku.co.jp", true),
        ("E nagisa sugimura@nipponkayaku.co.jp", "E nagisa.sugimura@nipponkayaku.co.jp", true),
        ("jane tan wei@acme.sg", "jane.tan.wei@acme.sg", true),
        ("Email: nagisa.sugimura@nipponkayaku.co.jp", "Email: nagisa.sugimura@nipponkayaku.co.jp", false),
        ("Tel 6123 4567 jane@acme.sg", "Tel 6123 4567 jane@acme.sg", false),
        ("Nagisa Sugimura nagisa@x.jp", "Nagisa Sugimura nagisa@x.jp", false),
        ("contact us at info@acme.sg", "contact us at info@acme.sg", false),
        ("no email here", "no email here", false),
    ])
    func emailSpacing(input: String, expected: String, repaired: Bool) {
        let result = TextCleanup.repairEmailSpacing(input)
        #expect(result.text == expected)
        #expect(result.repaired == repaired)
    }

    @Test(arguments: [
        ("NIPPON KAYAKU CO..LTD.", "NIPPON KAYAKU CO., LTD."),
        ("Acme Co.,Ltd.", "Acme Co., Ltd."),
        ("Level 12,One Raffles Place", "Level 12, One Raffles Place"),
        ("U.S.A.", "U.S.A."),
        ("Wait...", "Wait..."),
    ])
    func punctuation(input: String, expected: String) {
        #expect(TextCleanup.fixPunctuationSpacing(input) == expected)
    }

    @Test(arguments: [
        ("NIPPON KAYAKU CO..LTD.", "Nippon Kayaku Co., Ltd."),
        ("SENIOR MANAGER, R&D DEPT", "Senior Manager, R&D Dept"),
        ("HEAD OF SALES, APAC", "Head of Sales, APAC"),
        ("DBS BANK LTD", "DBS Bank Ltd"),
        ("MAJU TEKNOLOGI SDN BHD", "Maju Teknologi Sdn Bhd"),
        ("1-1 MARUNOUCHI, CHIYODA-KU\nTOKYO 100-0005", "1-1 Marunouchi, Chiyoda-ku\nTokyo 100-0005"),
        ("Acme ROBOTICS", "Acme ROBOTICS"),
        ("深圳市华星科技有限公司", "深圳市华星科技有限公司"),
    ])
    func capitalisation(input: String, expected: String) {
        #expect(TextCleanup.tidy(input) == expected)
    }

    @Test func namesCapitaliseEveryWordButParticles() {
        #expect(TextCleanup.tidy("NG", isName: true) == "Ng")
        #expect(TextCleanup.tidy("O'NEIL", isName: true) == "O'Neil")
        #expect(TextCleanup.tidy("BIN ISMAIL", isName: true) == "bin Ismail")
    }

    @Test func allCapsCardIsTidiedAndRepairedEmailIsFlagged() {
        let draft = parse([
            ("NIPPON KAYAKU CO..LTD.", 0.05), ("NAGISA SUGIMURA", 0.07), ("SENIOR MANAGER", 0.04),
            ("Email: nagisa sugimura@nipponkayaku.co.jp", 0.04), ("TEL +81 3 6731 5200", 0.04),
        ], region: "JP")
        #expect(draft.organization == "Nippon Kayaku Co., Ltd.")
        #expect(draft.givenName == "Nagisa")
        #expect(draft.familyName == "Sugimura")
        #expect(draft.jobTitle == "Senior Manager")
        #expect(draft.emails == ["nagisa.sugimura@nipponkayaku.co.jp"])
        #expect(draft.needsAttention(.emails))
    }

    @Test func useAsEmailRepairsSpacing() {
        var draft = DraftContact()
        draft.assign("Email: nagisa sugimura@nipponkayaku.co.jp", as: .email, region: "JP")
        #expect(draft.emails == ["nagisa.sugimura@nipponkayaku.co.jp"])
        draft.assign("NIPPON KAYAKU CO..LTD.", as: .organization, region: "JP")
        #expect(draft.organization == "Nippon Kayaku Co., Ltd.")
    }
}
