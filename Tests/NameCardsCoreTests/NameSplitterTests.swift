import Testing
@testable import NameCardsCore

@Suite struct NameSplitterTests {
    @Test(arguments: [
        ("Jane Tan", "", "Jane", "Tan", ""),
        ("Tan Mei Ling", "", "Mei Ling", "Tan", ""),
        ("TAN Mei Ling", "", "Mei Ling", "Tan", ""),
        ("Taro YAMADA", "", "Taro", "Yamada", ""),
        ("JOHN SMITH", "", "John", "Smith", ""),
        ("Ahmad bin Ismail", "", "Ahmad", "bin Ismail", ""),
        ("Ravi a/l Kumar", "", "Ravi", "a/l Kumar", ""),
        ("Dr. Sarah O'Neil", "Dr.", "Sarah", "O'Neil", ""),
        ("Dato' Sri Lim Kok Wing", "Dato' Sri", "Kok Wing", "Lim", ""),
        ("Jane Tan, PhD, CPA", "", "Jane", "Tan", "PhD, CPA"),
        ("Jane Tan MBA", "", "Jane", "Tan", "MBA"),
        ("Madonna", "", "Madonna", "", ""),
    ])
    func latin(name: String, prefix: String, given: String, family: String, suffix: String) {
        let parts = NameSplitter.split(name)
        #expect(parts.prefix == prefix)
        #expect(parts.given == given)
        #expect(parts.family == family)
        #expect(parts.suffix == suffix)
    }

    @Test func romanisedOfCJKPrefersSurnameFirst() {
        #expect(NameSplitter.split("Lin Chih-Hao", romanisedOfCJK: true).family == "Lin")
        #expect(NameSplitter.split("Lin Chih-Hao").family == "Chih-Hao")
        #expect(NameSplitter.split("David Tan", romanisedOfCJK: true).family == "Tan")
    }

    @Test(arguments: [
        ("陈美玲", false, "陈", "美玲"),
        ("欧阳娜娜", false, "欧阳", "娜娜"),
        ("林志豪", false, "林", "志豪"),
        ("山田 太郎", false, "山田", "太郎"),
        ("山田太郎", true, "山田", "太郎"),
        ("김민준", false, "김", "민준"),
        ("남궁민수", false, "남궁", "민수"),
    ])
    func cjk(name: String, japanese: Bool, family: String, given: String) {
        let parts = NameSplitter.split(name, japaneseContext: japanese)
        #expect(parts.family == family)
        #expect(parts.given == given)
    }
}
