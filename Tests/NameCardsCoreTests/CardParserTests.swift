import Testing
@testable import NameCardsCore

/// Fixtures are real Vision OCR output from rendered sample cards (see TextRecognizerTests), plus edge cases.
@Suite struct CardParserTests {
    @Test func singaporeEnglishCard() {
        let draft = parse([
            ("ACME ROBOTICS", 0.060), ("Jane Tan", 0.054), ("Senior Product Manager", 0.043),
            ("T +65 6123 4567 M +65 9123 4567", 0.040), ("jane.tan@acmerobotics.com.sg", 0.040),
            ("www.acmerobotics.com.sg", 0.037), ("1 Raffles Place, #20-01 One Raffles Place", 0.047),
            ("Singapore 048616", 0.048),
        ])
        #expect(draft.givenName == "Jane")
        #expect(draft.familyName == "Tan")
        #expect(draft.confidence(for: .name) >= 0.9)
        #expect(draft.jobTitle == "Senior Product Manager")
        #expect(draft.organization == "ACME ROBOTICS")
        #expect(draft.phones == [
            Phone(number: "+6561234567", raw: "+65 6123 4567", kind: .work),
            Phone(number: "+6591234567", raw: "+65 9123 4567", kind: .mobile),
        ])
        #expect(draft.emails == ["jane.tan@acmerobotics.com.sg"])
        #expect(draft.urls == ["www.acmerobotics.com.sg"])
        #expect(draft.address == "1 Raffles Place, #20-01 One Raffles Place\nSingapore 048616")
    }

    @Test func malaysianCardUsesCardRegionAndPatronymic() {
        let draft = parse([
            ("Ahmad bin Ismail", 0.053), ("Business Development Director", 0.043), ("Maju Teknologi Sdn Bhd", 0.053),
            ("Level 15, Menara Maju", 0.040), ("Jalan Ampang", 0.041), ("50450 Kuala Lumpur, Malaysia", 0.040),
            ("Tel: 03-2161 1234 Fax: 03-2161 1235", 0.037), ("H/P: 012-345 6789", 0.037),
            ("ahmad@majutek.com.my", 0.037),
        ], region: "SG")
        #expect(draft.givenName == "Ahmad")
        #expect(draft.familyName == "bin Ismail")
        #expect(draft.organization == "Maju Teknologi Sdn Bhd")
        #expect(draft.jobTitle == "Business Development Director")
        #expect(draft.phones.map(\.number) == ["+60321611234", "+60321611235", "+60123456789"])
        #expect(draft.phones.map(\.kind) == [.work, .fax, .mobile])
        #expect(draft.address == "Level 15, Menara Maju\nJalan Ampang\n50450 Kuala Lumpur, Malaysia")
    }

    @Test func simplifiedChineseBilingualCard() {
        let draft = parse([
            ("深圳市华星科技有限公司", 0.055), ("陈美玲", 0.083), ("Tan Mei Ling", 0.047), ("市场部 总监", 0.043),
            ("手机：138 0013 8000", 0.040), ("电话：0755-8888 6666", 0.040),
            ("邮箱：meiling.tan@huaxingtech.cn", 0.040), ("地址：深圳市南山区科技园路1号华星大厦8楼", 0.037),
        ])
        #expect(draft.familyName == "陈")
        #expect(draft.givenName == "美玲")
        #expect(draft.phoneticFamilyName == "Tan")
        #expect(draft.phoneticGivenName == "Mei Ling")
        #expect(draft.organization == "深圳市华星科技有限公司")
        #expect(draft.jobTitle == "总监")
        #expect(draft.department == "市场部")
        #expect(draft.phones == [
            Phone(number: "+8613800138000", raw: "138 0013 8000", kind: .mobile),
            Phone(number: "+8675588886666", raw: "0755-8888 6666", kind: .work),
        ])
        #expect(draft.emails == ["meiling.tan@huaxingtech.cn"])
        #expect(draft.address == "深圳市南山区科技园路1号华星大厦8楼")
    }

    @Test func traditionalChineseCardWithLabelOnItsOwnLine() {
        let draft = parse([
            ("台灣雲端資訊股份有限公司", 0.055), ("林志豪", 0.083), ("Lin Chih-Hao", 0.040), ("業務部 經理", 0.043),
            ("電話：（02）2345-6789分機123", 0.037), ("手機：", 0.037), ("0912-345-678", 0.037),
            ("郵箱：chihhao.lin@twcloud.com.tw", 0.037), ("地址：台北市信義區信義路五段7號35樓", 0.037),
        ])
        #expect(draft.familyName == "林")
        #expect(draft.givenName == "志豪")
        #expect(draft.phoneticFamilyName == "Lin")
        #expect(draft.phoneticGivenName == "Chih-Hao")
        #expect(draft.organization == "台灣雲端資訊股份有限公司")
        #expect(draft.department == "業務部")
        #expect(draft.jobTitle == "經理")
        #expect(draft.phones.map(\.number) == ["+886223456789", "+886912345678"])
        #expect(draft.phones.map(\.kind) == [.work, .mobile])
        #expect(draft.address == "台北市信義區信義路五段7號35樓")
    }

    @Test func japaneseCardWithReadingAndPostcode() {
        let draft = parse([
            ("株式会社サクラデザイン", 0.050), ("デザイン部部長", 0.037), ("山田 太郎", 0.075), ("やまだ たろう", 0.031),
            ("Taro YAMADA", 0.033), ("〒150-0002 東京都渋谷区渋谷2-21-1", 0.037),
            ("TEL 03-1234-5678 携帯 090-1234-5678", 0.037), ("yamada@sakura-design.co.jp", 0.037),
        ])
        #expect(draft.familyName == "山田")
        #expect(draft.givenName == "太郎")
        #expect(draft.phoneticFamilyName == "やまだ")
        #expect(draft.phoneticGivenName == "たろう")
        #expect(draft.nickname == "Taro YAMADA")
        #expect(draft.organization == "株式会社サクラデザイン")
        #expect(draft.jobTitle == "デザイン部部長")
        #expect(draft.phones == [
            Phone(number: "+81312345678", raw: "03-1234-5678", kind: .work),
            Phone(number: "+819012345678", raw: "090-1234-5678", kind: .mobile),
        ])
        #expect(draft.address == "〒150-0002 東京都渋谷区渋谷2-21-1")
    }

    @Test func koreanCard() {
        let draft = parse([
            ("한빛소프트 주식회사", 0.050), ("김민준", 0.072), ("개발팀 팀장", 0.038),
            ("서울특별시 강남구 테헤란로 123, 10층", 0.035), ("전화 02-555-1234", 0.035),
            ("휴대폰 010-9876-5432", 0.035), ("minjun.kim@hanbitsoft.co.kr", 0.035),
        ])
        #expect(draft.familyName == "김")
        #expect(draft.givenName == "민준")
        #expect(draft.organization == "한빛소프트 주식회사")
        #expect(draft.department == "개발팀")
        #expect(draft.jobTitle == "팀장")
        #expect(draft.phones.map(\.number) == ["+8225551234", "+821098765432"])
        #expect(draft.phones.map(\.kind) == [.work, .mobile])
        #expect(draft.address == "서울특별시 강남구 테헤란로 123, 10층")
    }

    @Test func honorificsCredentialsAndAllCapsName() {
        let draft = parse([("DR. JOHN SMITH, PHD", 0.06), ("Chief Technology Officer", 0.04), ("Globex Pte Ltd", 0.05),
                           ("john@globex.sg", 0.04)])
        #expect(draft.namePrefix == "DR.")
        #expect(draft.givenName == "John")
        #expect(draft.familyName == "Smith")
        #expect(draft.nameSuffix == "PHD")
        #expect(draft.organization == "Globex Pte Ltd")
    }

    @Test func bareSingleLetterLabelsAreStripped() {
        let draft = parse([("Wei Ming Lim", 0.06), ("T 6123 4567 F 6123 4568", 0.04), ("E wm.lim@example.sg", 0.04)])
        #expect(draft.phones.map(\.kind) == [.work, .fax])
        #expect(draft.phones.map(\.number) == ["+6561234567", "+6561234568"])
        #expect(draft.emails == ["wm.lim@example.sg"])
        #expect(draft.rawLines.count == 3)
        #expect(draft.givenName == "Wei Ming")
        #expect(draft.familyName == "Lim")
    }

    @Test func spacedOcrEmailIsRepaired() {
        let draft = parse([("Sam Lee", 0.06), ("sam.lee @ widgets.io", 0.04)])
        #expect(draft.emails == ["sam.lee@widgets.io"])
    }

    @Test func companyFromDomainWhenNoLegalSuffix() {
        let draft = parse([("Northwind", 0.04), ("Priya Raman", 0.06), ("Account Executive", 0.04),
                           ("priya@northwind.com", 0.04)])
        #expect(draft.organization == "Northwind")
        #expect(draft.givenName == "Priya")
        #expect(draft.jobTitle == "Account Executive")
    }

    @Test func nameGuessedFromEmailWhenNotPrinted() {
        let draft = parse([("+65 9876 5432", 0.04), ("alex.wong@example.com", 0.04)])
        #expect(draft.givenName == "Alex")
        #expect(draft.familyName == "Wong")
        #expect(draft.confidence(for: .name) < 0.5)
    }

    @Test func surnameFirstRomanisedName() {
        let draft = parse([("TAN Mei Ling", 0.06), ("Director", 0.04)])
        #expect(draft.familyName == "Tan")
        #expect(draft.givenName == "Mei Ling")
    }

    @Test func fullWidthCharactersAreNormalised() {
        let draft = parse([("田中 花子", 0.07), ("ＴＥＬ　０３－１２３４－５６７８", 0.04), ("hanako@example.co.jp", 0.04)])
        #expect(draft.phones.first?.number == "+81312345678")
    }

    @Test(arguments: [
        (["jane@acme.com.my"], "MY"), (["Singapore 048616"], "SG"), (["〒150-0002 東京都"], "JP"),
        (["서울특별시 강남구"], "KR"), (["www.foo.com.hk"], "HK"), (["hello"], nil),
    ] as [([String], String?)])
    func regionInference(texts: [String], expected: String?) {
        #expect(CardParser.inferRegion(from: texts) == expected)
    }
}
