import Foundation

/// Splits a printed personal name into Contacts' structured fields.
public enum NameSplitter {
    public struct Parts: Equatable, Sendable {
        public var prefix = ""
        public var given = ""
        public var family = ""
        public var suffix = ""
        /// How sure the split is (word order is ambiguous for some names).
        public var confidence = 1.0
    }

    /// Common surnames that are printed first in romanised Chinese, Korean and Vietnamese names.
    static let surnameFirstRomanised: Set<String> = [
        "tan", "lim", "lee", "ng", "ong", "wong", "goh", "chua", "chan", "koh", "teo", "ang", "yeo", "tay", "ho",
        "low", "toh", "sim", "chong", "leong", "foo", "chin", "yap", "teh", "liew", "khoo", "cheah", "chew", "lau",
        "loh", "soh", "seah", "kwok", "lai", "yong", "wee", "heng", "chia", "phua", "quek", "pang", "chen", "wang",
        "li", "zhang", "liu", "yang", "huang", "zhao", "wu", "zhou", "xu", "sun", "ma", "zhu", "hu", "guo", "he",
        "lin", "luo", "gao", "zheng", "liang", "xie", "song", "tang", "han", "feng", "deng", "cao", "peng", "zeng",
        "xiao", "tian", "dong", "pan", "yuan", "cai", "jiang", "yu", "du", "ye", "cheng", "wei", "su", "lu", "ding",
        "ren", "shen", "yao", "kim", "park", "choi", "jung", "kang", "cho", "yoon", "jang", "shin", "nguyen", "tran",
        "le", "pham", "hoang", "phan", "vu", "dang", "bui", "do", "huynh", "cheung", "leung", "kwan", "fong", "yip",
        "tse", "chow", "lam", "mak", "siu", "tsang", "kok", "hew", "liow", "gan", "yee", "neo", "poh", "tng",
    ]

    static let chineseCompoundSurnames: Set<String> = [
        "欧阳", "歐陽", "司马", "司馬", "诸葛", "諸葛", "上官", "东方", "東方", "皇甫", "尉迟", "尉遲", "公孙", "公孫",
        "慕容", "长孙", "長孫", "夏侯", "令狐", "宇文", "司徒", "西门", "西門", "端木",
    ]

    static let koreanCompoundSurnames: Set<String> = ["남궁", "황보", "제갈", "선우", "독고", "사공", "서문"]

    /// - Parameters:
    ///   - japaneseContext: the card contains kana, so unspaced kanji names follow Japanese surname lengths.
    ///   - romanisedOfCJK: the name is the Latin rendering of a CJK name on the same card, which makes
    ///     surname-first order ("Lin Chih-Hao") likely when the first word is a known surname.
    public static func split(_ name: String, japaneseContext: Bool = false, romanisedOfCJK: Bool = false) -> Parts {
        let name = name.collapsingWhitespace
        if name.cjkCount > 0 && name.latinCount == 0 {
            return splitCJK(name, japanese: japaneseContext || name.containsKana)
        }
        return splitLatin(name, romanisedOfCJK: romanisedOfCJK)
    }

    // MARK: Latin

    static func splitLatin(_ name: String, romanisedOfCJK: Bool = false) -> Parts {
        var parts = Parts()
        var text = name

        // Credentials after a comma: "Jane Tan, PhD, CPA".
        if let comma = text.firstIndex(of: ",") {
            parts.suffix = String(text[text.index(after: comma)...]).trimmed
            text = String(text[..<comma])
        }

        var tokens = text.split(separator: " ").map(String.init)

        // Honorifics, longest first so multi-word ones ("Tan Sri", "Datuk Seri") win.
        for prefix in Keywords.namePrefixes.sorted(by: { $0.count > $1.count }) {
            let prefixTokens = prefix.split(separator: " ").map(String.init)
            guard tokens.count > prefixTokens.count else { continue }
            let head = tokens.prefix(prefixTokens.count).map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            if head == prefixTokens.map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }) {
                parts.prefix = tokens.prefix(prefixTokens.count).joined(separator: " ")
                tokens.removeFirst(prefixTokens.count)
                break
            }
        }

        // Trailing credentials without a comma: "Jane Tan PhD".
        while tokens.count > 1, Keywords.nameSuffixes.contains(tokens.last!.lowercased()) {
            let suffix = tokens.removeLast()
            parts.suffix = parts.suffix.isEmpty ? suffix : suffix + ", " + parts.suffix
        }

        guard !tokens.isEmpty else { return parts }
        if tokens.count == 1 {
            parts.given = titleCasedIfShouting(tokens[0], allTokensUpper: true)
            parts.confidence = 0.6
            return parts
        }

        // Malay/Tamil patronymics: "Ahmad bin Ismail", "Ravi a/l Kumar".
        if let particle = tokens.firstIndex(where: { Keywords.nameParticles.contains($0.lowercased()) }), particle > 0 {
            parts.given = tokens[..<particle].joined(separator: " ")
            parts.family = tokens[particle...].joined(separator: " ")
            return parts
        }

        let isUpper = tokens.map { $0.count >= 2 && $0 == $0.uppercased() && $0.latinCount > 0 }
        let allUpper = isUpper.allSatisfy { $0 }
        let cased = tokens.map { titleCasedIfShouting($0, allTokensUpper: allUpper) }

        // "TAN Mei Ling" / "Taro YAMADA": a single all-caps token marks the family name.
        if !allUpper, isUpper.filter({ $0 }).count == 1, let index = isUpper.firstIndex(of: true) {
            parts.family = cased[index]
            parts.given = cased.enumerated().filter { $0.offset != index }.map(\.element).joined(separator: " ")
            return parts
        }

        // "Tan Mei Ling": known surname first followed by a two-part given name.
        let surnameFirst = surnameFirstRomanised.contains(tokens[0].lowercased())
            && !surnameFirstRomanised.contains(tokens.last!.lowercased())
        if surnameFirst && (tokens.count == 3 || romanisedOfCJK) {
            parts.family = cased[0]
            parts.given = cased[1...].joined(separator: " ")
            parts.confidence = 0.7
            return parts
        }

        parts.family = cased.last!
        parts.given = cased.dropLast().joined(separator: " ")
        parts.confidence = tokens.count == 2 ? 0.8 : 0.7
        return parts
    }

    /// "JANE" → "Jane" when the whole name is in capitals; mixed-case tokens like "McDonald" are kept.
    private static func titleCasedIfShouting(_ token: String, allTokensUpper: Bool) -> String {
        guard token == token.uppercased(), token.count > 1 else { return token }
        return token.lowercased().split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: "-")
    }

    // MARK: CJK

    static func splitCJK(_ name: String, japanese: Bool) -> Parts {
        var parts = Parts()
        let tokens = name.split(separator: " ").map(String.init)
        if tokens.count >= 2 {
            parts.family = tokens[0]
            parts.given = tokens[1...].joined()
            return parts
        }

        let characters = Array(name)
        let familyLength: Int
        if name.containsHangul {
            familyLength = koreanCompoundSurnames.contains(String(characters.prefix(2))) && characters.count > 3 ? 2 : 1
            parts.confidence = 0.9
        } else if japanese {
            // Most Japanese surnames are two kanji; three-character names are genuinely ambiguous.
            familyLength = characters.count <= 2 ? 1 : 2
            parts.confidence = characters.count == 4 ? 0.8 : 0.5
        } else {
            familyLength = chineseCompoundSurnames.contains(String(characters.prefix(2))) && characters.count > 2 ? 2 : 1
            parts.confidence = 0.9
        }
        guard characters.count > familyLength else {
            parts.given = name
            parts.confidence = 0.5
            return parts
        }
        parts.family = String(characters.prefix(familyLength))
        parts.given = String(characters.dropFirst(familyLength))
        return parts
    }
}
