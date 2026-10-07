import Foundation

/// Fixes common OCR and typesetting artefacts in card text.
public enum TextCleanup {
    // MARK: Email

    /// Rejoins an email whose dots OCR read as spaces: "Email: nagisa sugimura@x.co.jp" → "Email: nagisa.sugimura@x.co.jp".
    /// Joins up to three lowercase words directly before the "@", stopping at labels and ordinary words.
    public static func repairEmailSpacing(_ line: String) -> (text: String, repaired: Bool) {
        guard let at = line.firstIndex(of: "@") else { return (line, false) }
        var tokens = line[..<at].split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let last = tokens.last, isLocalPart(last) else { return (line, false) }
        var parts = [tokens.removeLast()]
        while parts.count < 3, let previous = tokens.last, isLocalPart(previous), !emailStopWords.contains(previous) {
            parts.insert(tokens.removeLast(), at: 0)
        }
        guard parts.count > 1 else { return (line, false) }
        let rebuilt = (tokens + [parts.joined(separator: ".")]).joined(separator: " ") + line[at...]
        return (rebuilt, true)
    }

    private static let emailStopWords: Set<String> = Set(Keywords.emailLabels)
        .union(["at", "or", "and", "to", "us", "me", "via"])

    /// Lowercase local-part characters with at least one letter (so "4567" in "Tel 6123 4567 a@b" isn't joined).
    private static func isLocalPart(_ token: String) -> Bool {
        !token.isEmpty && token.contains(where: \.isLetter)
            && token.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || "._%+-".contains($0) }
    }

    // MARK: Punctuation

    /// Puts a space after runs of punctuation that run into the next word: "CO.,LTD." → "CO., LTD.",
    /// and reads OCR's ".." (a misread "., ") as such: "CO..LTD." → "CO., LTD.". Single dots are left
    /// alone so abbreviations like "U.S.A." survive.
    public static func fixPunctuationSpacing(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: #"(?<=\p{L})(?<!\.)\.\.(?!\.)(?=\s*\p{L})"#, with: ".,",
                                             options: .regularExpression)
        result = result.replacingOccurrences(of: #"([.,;:]{2,}|,)(?=\p{L})"#, with: "$1 ", options: .regularExpression)
        return result.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
    }

    // MARK: Capitalisation

    /// Acronyms kept in capitals when a field is converted from all caps.
    static let keepUpper: Set<String> = [
        "CEO", "CTO", "CFO", "COO", "CMO", "CIO", "CISO", "CPO", "VP", "SVP", "EVP", "AVP", "GM", "MD", "HR", "IT",
        "PR", "QA", "UX", "UI", "AI", "ML", "R&D", "USA", "UK", "EU", "UAE", "LLC", "LLP", "LP", "PLC", "KK",
        "II", "III", "IV", "ASEAN", "APAC", "EMEA", "HQ", "PO", "ICT", "IOT", "SAP", "AWS",
    ]

    /// Vowel-less abbreviations that are still words, so they're title-cased rather than kept as acronyms.
    static let titleAbbreviations: Set<String> = [
        "LTD", "BHD", "SDN", "PTY", "ST", "RD", "JLN", "BLVD", "DR", "MR", "MRS", "MS", "FL", "FLR", "BLDG",
        "BLK", "CTR", "DEPT", "MGR", "SR", "JR", "NO", "LVL",
    ]

    /// Small words lowercased inside a title ("Head of Sales").
    static let minorWords: Set<String> = ["OF", "AND", "THE", "FOR", "IN", "AT", "ON", "TO", "DE", "VON", "VAN", "BIN", "BINTI"]

    /// Converts an all-caps Latin string to capital case ("NIPPON KAYAKU CO., LTD." → "Nippon Kayaku Co., Ltd.").
    /// Text with any lowercase letter is returned unchanged. For names (`isName`), every word is
    /// capitalised, since short surnames like "NG" aren't acronyms.
    public static func capitalisingIfAllCaps(_ text: String, isName: Bool = false) -> String {
        let latinLetters = text.filter { $0.isLetter && $0.isASCII }
        guard latinLetters.count >= 2, !text.contains(where: \.isLowercase) else { return text }
        var isFirstWord = true
        return text.split(separator: " ", omittingEmptySubsequences: false).map { token in
            defer { if token.contains(where: \.isLetter) { isFirstWord = false } }
            return capitaliseToken(String(token), isName: isName, isFirstWord: isFirstWord)
        }.joined(separator: " ")
    }

    private static func capitaliseToken(_ token: String, isName: Bool, isFirstWord: Bool) -> String {
        guard token.contains(where: { $0.isLetter && $0.isASCII }) else { return token }
        let core = token.trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "&'")))
        let key = core.replacingOccurrences(of: ".", with: "")
        if isName && Keywords.nameParticles.contains(key.lowercased()) { return token.lowercased() }
        if !isName {
            if keepUpper.contains(key) { return token }
            if core.contains(where: \.isNumber) { return token }
            if minorWords.contains(key) && !isFirstWord { return token.lowercased() }
            let hasVowel = key.contains { "AEIOUY".contains($0) }
            if !hasVowel && key.count >= 2 && !titleAbbreviations.contains(key) { return token }
        }
        // Capitalise the first letter; also the letter after a leading "O'" / "D'".
        var characters = Array(token.lowercased())
        if let first = characters.firstIndex(where: \.isLetter) {
            characters[first] = Character(characters[first].uppercased())
            let apostrophe = characters.index(first, offsetBy: 1)
            if apostrophe + 1 < characters.count, characters[apostrophe] == "'" {
                characters[apostrophe + 1] = Character(characters[apostrophe + 1].uppercased())
            }
        }
        return String(characters)
    }

    /// Punctuation spacing, then capital case for an all-caps field; multi-line text is handled line by line.
    public static func tidy(_ text: String, isName: Bool = false) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { capitalisingIfAllCaps(fixPunctuationSpacing(String($0)), isName: isName) }
            .joined(separator: "\n")
    }
}

extension DraftContact {
    /// Applies `TextCleanup.tidy` to every free-text field (not emails, websites or phones).
    public func tidied() -> DraftContact {
        var draft = self
        for keyPath in [\DraftContact.givenName, \.familyName, \.phoneticGivenName, \.phoneticFamilyName, \.nickname] {
            draft[keyPath: keyPath] = TextCleanup.tidy(draft[keyPath: keyPath], isName: true)
        }
        for keyPath in [\DraftContact.jobTitle, \.department, \.organization, \.address] {
            draft[keyPath: keyPath] = TextCleanup.tidy(draft[keyPath: keyPath])
        }
        return draft
    }
}
