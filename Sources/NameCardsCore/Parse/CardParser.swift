import Foundation

/// Rule-based extraction of contact fields from OCR lines. Pure and deterministic: same lines in, same draft out.
///
/// Pass order: normalise text → pull out emails, URLs and phones → classify what's left (address, company,
/// title, department) → pick the person's name from the remaining candidates → fall back for the company.
public struct CardParser: Sendable {
    /// ISO region used for numbers printed without a country code, unless the card itself
    /// indicates another country (email/web domain, address, script).
    public var region: String

    public init(region: String = Locale.current.region?.identifier ?? "US") {
        self.region = region
    }

    struct Item {
        var text: String
        let index: Int
        /// Line height relative to the tallest line on the card (font-size proxy).
        let relativeHeight: Double
    }

    public func parse(_ lines: [OCRLine]) -> DraftContact {
        var draft = DraftContact()
        let maxHeight = max(lines.map(\.box.height).max() ?? 1, 0.0001)
        var items = lines.enumerated().map { index, line in
            Item(text: Self.normalize(line.text), index: index, relativeHeight: Double(line.box.height / maxHeight))
        }.filter { !$0.text.isEmpty }
        draft.rawLines = items.map(\.text)
        let japanese = items.contains { $0.text.containsKana }

        let cardRegion = Self.inferRegion(from: draft.rawLines) ?? region
        items = extractContactDetails(from: items, region: cardRegion, into: &draft)

        // Classify remaining lines.
        var addressLines: [Item] = []
        var companyLines: [Item] = []
        var titleLines: [Item] = []
        var departmentLines: [Item] = []
        var candidates: [Item] = []
        for item in items {
            switch Self.classify(item.text) {
            case .address(let text): addressLines.append(Item(text: text, index: item.index, relativeHeight: item.relativeHeight))
            case .company: companyLines.append(item)
            case .title: titleLines.append(item)
            case .department: departmentLines.append(item)
            case .candidate: candidates.append(item)
            }
        }
        absorbAddressContinuations(addressLines: &addressLines, candidates: &candidates)

        let domainStems = Self.domainStems(emails: draft.emails, urls: draft.urls)
        let nameIsCJK = assignName(from: &candidates, domainStems: domainStems, japanese: japanese, into: &draft)

        if let company = Self.preferred(companyLines, cjk: nameIsCJK) {
            draft.organization = company.text
            draft.confidence[.organization] = 0.85
        } else if let index = candidates.firstIndex(where: { Self.domainAffinity($0.text, stems: domainStems) }) {
            draft.organization = candidates.remove(at: index).text
            draft.confidence[.organization] = 0.7
        } else if let tallest = candidates.max(by: { $0.relativeHeight < $1.relativeHeight }),
                  tallest.relativeHeight >= 0.8 {
            // Large leftover text is usually the logo/company name.
            draft.organization = tallest.text
            draft.confidence[.organization] = 0.4
        } else if let stem = domainStems.first {
            draft.organization = stem.prefix(1).uppercased() + stem.dropFirst()
            draft.confidence[.organization] = 0.3
        }

        if let title = Self.preferred(titleLines, cjk: nameIsCJK) {
            let (department, jobTitle) = Self.splitDepartment(fromTitle: title.text)
            draft.jobTitle = jobTitle
            draft.confidence[.jobTitle] = 0.8
            if let department {
                departmentLines.insert(Item(text: department, index: title.index, relativeHeight: title.relativeHeight), at: 0)
            }
        }
        if let department = Self.preferred(departmentLines, cjk: nameIsCJK) {
            draft.department = department.text
            draft.confidence[.department] = 0.7
        }
        if !addressLines.isEmpty {
            draft.address = addressLines.sorted { $0.index < $1.index }.map(\.text).joined(separator: "\n")
            draft.confidence[.address] = 0.7
        }
        return draft.tidied()
    }

    // MARK: - Normalisation

    static func normalize(_ text: String) -> String {
        // NFKC folds full-width forms (ＴＥＬ０３) and enclosed ideographs (㈱ → (株)) into plain text.
        var text = text.precomposedStringWithCompatibilityMapping
        text = text.replacingOccurrences(of: #"\s*@\s*"#, with: "@", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s*[(\[]at[)\]]\s*"#, with: "@", options: [.regularExpression, .caseInsensitive])
        return text.collapsingWhitespace
    }

    // MARK: - Emails, URLs, phones

    private static let emailPattern = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}"#)
    private static let urlPattern = try! NSRegularExpression(
        pattern: #"(?i)(?:https?://)?(?:www\.)?[a-z0-9][a-z0-9\-]*(?:\.[a-z0-9\-]+)*\.(?:com|net|org|io|co|ai|biz|info|edu|gov|app|dev|tech|asia|xyz|me|my|sg|cn|hk|tw|jp|kr|uk|au|id|th|ph|vn|in)(?:\.[a-z]{2})?(?![a-z0-9\-])(?:/[^\s]*)?"#)

    /// Moves emails, URLs and phone numbers into `draft` and returns the lines with those parts removed.
    private func extractContactDetails(from items: [Item], region: String, into draft: inout DraftContact) -> [Item] {
        var remaining: [Item] = []
        var emailsRepaired = false
        // Vision sometimes reads a label ("手機：") as its own line, separate from the number after it.
        var pendingKind: Phone.Kind?
        for var item in items {
            if Self.stripLabels(item.text, allowBareSingleLetters: true).isEmpty,
               let kind = PhoneNumbers.kind(forPrecedingText: item.text) {
                pendingKind = kind
                continue
            }
            var (text, repairedEmail) = TextCleanup.repairEmailSpacing(item.text)
            var extracted = false

            for match in Self.matches(Self.emailPattern, in: text).reversed() {
                let email = String(text[match]).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if !draft.emails.contains(email) { draft.emails.append(email) }
                text.replaceSubrange(match, with: " ")
                extracted = true
                emailsRepaired = emailsRepaired || repairedEmail
            }
            for match in Self.matches(Self.urlPattern, in: text).reversed() {
                let url = String(text[match]).trimmingCharacters(in: CharacterSet(charactersIn: ".,/"))
                if !draft.urls.contains(where: { $0.caseInsensitiveCompare(url) == .orderedSame }) {
                    draft.urls.append(url.lowercased())
                }
                text.replaceSubrange(match, with: " ")
                extracted = true
            }
            var phones = PhoneNumbers.find(in: text, region: region)
            if let kind = pendingKind, let first = phones.first, !first.labelled {
                phones[0].phone.kind = kind
            }
            pendingKind = nil
            for match in phones.reversed() {
                text.replaceSubrange(match.range, with: " ")
            }
            for match in phones where !draft.phones.contains(where: { $0.number == match.phone.number }) {
                draft.phones.append(match.phone)
            }
            extracted = extracted || !phones.isEmpty

            if extracted {
                // Whatever is left is usually just labels ("T:", "E |"); keep it only if real text remains.
                text = Self.stripLabels(text, allowBareSingleLetters: true)
                guard text.latinCount + text.cjkCount >= 2 else { continue }
            }
            item.text = text.collapsingWhitespace
            remaining.append(item)
        }
        // A rejoined email ("nagisa sugimura@" → "nagisa.sugimura@") is a guess the user should check.
        if !draft.emails.isEmpty { draft.confidence[.emails] = emailsRepaired ? 0.5 : 0.95 }
        if !draft.urls.isEmpty { draft.confidence[.urls] = 0.9 }
        if !draft.phones.isEmpty {
            draft.confidence[.phones] = draft.phones.allSatisfy(\.isNormalized) ? 0.9 : 0.6
        }
        return remaining
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> [Range<String.Index>] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
    }

    private static let separators = CharacterSet.whitespaces.union(.punctuationCharacters).union(.symbols)
        .union(CharacterSet(charactersIn: "：|·•"))

    /// Repeatedly removes leading/trailing contact labels ("Tel:", "E", "地址：").
    /// Bare single letters ("T 6123…") are only stripped from lines that held contact details,
    /// so a name initial like "A Tan" is never eaten elsewhere.
    static func stripLabels(_ text: String, allowBareSingleLetters: Bool) -> String {
        var text = text.trimmingCharacters(in: separators)
        let labels = Keywords.allLabels.sorted { $0.count > $1.count }
        var changed = true
        while changed, !text.isEmpty {
            changed = false
            let lower = text.lowercased()
            for label in labels where lower.hasPrefix(label) {
                let rest = text.dropFirst(label.count)
                let next = rest.first
                let isCJK = label.cjkCount > 0 || label == "〒"
                let boundary = next.map { !$0.isWordCharacter } ?? true
                let hasColon = next.map { ":：".contains($0) } ?? false
                // Without a colon, Latin words like "Office" or an initial "A" may be real content.
                guard isCJK || (boundary && (hasColon || allowBareSingleLetters)) else { continue }
                text = String(rest).trimmingCharacters(in: separators)
                changed = true
                break
            }
            if allowBareSingleLetters, !changed {
                let words = text.split(separator: " ")
                if let last = words.last, words.count > 1, labels.contains(last.lowercased()
                    .trimmingCharacters(in: separators)) {
                    text = words.dropLast().joined(separator: " ").trimmingCharacters(in: separators)
                    changed = true
                }
            }
        }
        return text
    }

    /// "市场部 总监" → ("市场部", "总监"); other titles pass through unchanged.
    static func splitDepartment(fromTitle title: String) -> (department: String?, title: String) {
        let tokens = title.split(separator: " ").map(String.init)
        guard tokens.count >= 2, title.isPureCJK,
              let index = tokens.firstIndex(where: { token in
                  token.last.map(Keywords.departmentSuffixes.contains) == true
                      && !Keywords.line(token, containsAnyOf: Keywords.title)
              })
        else { return (nil, title) }
        var rest = tokens
        let department = rest.remove(at: index)
        return (department, rest.joined(separator: " "))
    }

    // MARK: - Region

    private static let regionByTLD: [String: String] = [
        "sg": "SG", "my": "MY", "cn": "CN", "hk": "HK", "mo": "MO", "tw": "TW", "jp": "JP", "kr": "KR", "au": "AU",
        "uk": "GB", "nz": "NZ", "id": "ID", "th": "TH", "ph": "PH", "vn": "VN", "in": "IN", "de": "DE", "fr": "FR",
        "ca": "CA", "us": "US",
    ]

    /// Ordered most-specific first, since "Hong Kong" cards may also say "China".
    private static let regionByPlace: [(String, String)] = [
        ("singapore", "SG"), ("新加坡", "SG"), ("malaysia", "MY"), ("马来西亚", "MY"), ("馬來西亞", "MY"),
        ("kuala lumpur", "MY"), ("hong kong", "HK"), ("香港", "HK"), ("macau", "MO"), ("澳門", "MO"),
        ("taiwan", "TW"), ("台灣", "TW"), ("台湾", "TW"), ("台北", "TW"), ("臺北", "TW"), ("japan", "JP"),
        ("日本", "JP"), ("東京", "JP"), ("〒", "JP"), ("korea", "KR"), ("대한민국", "KR"), ("서울", "KR"),
        ("china", "CN"), ("中国", "CN"), ("北京", "CN"), ("上海", "CN"), ("深圳", "CN"), ("广州", "CN"),
        ("australia", "AU"), ("united kingdom", "GB"), ("indonesia", "ID"), ("thailand", "TH"),
        ("philippines", "PH"), ("vietnam", "VN"), ("india", "IN"), ("new zealand", "NZ"),
    ]

    /// The card's own country, used to read phone numbers printed without a country code.
    public static func inferRegion(from texts: [String]) -> String? {
        let joined = texts.joined(separator: "\n")
        let lower = joined.lowercased()
        if let place = regionByPlace.first(where: { lower.containsWord($0.0) || ($0.0.cjkCount > 0 || $0.0 == "〒") && lower.contains($0.0) }) {
            return place.1
        }
        let hosts = matches(emailPattern, in: joined).compactMap { joined[$0].split(separator: "@").last }
            + matches(urlPattern, in: joined).map { joined[$0][...] }
        for host in hosts {
            let labels = host.lowercased().split(separator: "/").first?.split(separator: ".") ?? []
            if let tld = labels.last, let region = regionByTLD[String(tld)] { return region }
        }
        if joined.containsKana { return "JP" }
        if joined.containsHangul { return "KR" }
        return nil
    }

    // MARK: - Line classification

    enum LineKind: Equatable {
        case address(String), company, title, department, candidate
    }

    static func classify(_ text: String) -> LineKind {
        let unlabelled = stripLabels(text, allowBareSingleLetters: false)
        if unlabelled != text.trimmingCharacters(in: separators),
           Keywords.line(String(text.prefix(text.count - unlabelled.count)), containsAnyOf: Keywords.addressLabels) {
            return .address(unlabelled)
        }
        if text.hasPrefix("〒") || isStrongAddress(text) { return .address(text) }
        if Keywords.line(text, containsAnyOf: Keywords.strongCompany) { return .company }
        if Keywords.line(text, containsAnyOf: Keywords.title) { return .title }
        if Keywords.line(text, containsAnyOf: Keywords.weakCompany) { return .company }
        if Keywords.line(text, containsAnyOf: Keywords.department) { return .department }
        if text.isPureCJK, text.count <= 10, let last = text.last, Keywords.departmentSuffixes.contains(last) {
            return .department
        }
        return .candidate
    }

    private static let postalCode = try! NSRegularExpression(pattern: #"(?<![\d-])\d{5,6}(?![\d-])"#)
    private static let unitNumber = try! NSRegularExpression(pattern: #"#\s?\d{1,3}-\d{1,5}"#)

    static func isStrongAddress(_ text: String) -> Bool {
        let lower = text.lowercased()
        if text.cjkCount > 0 {
            let markers = text.filter { Keywords.cjkAddress.contains($0) }.count
            let hasNumber = text.digitCount > 0 || text.contains { "一二三四五六七八九十".contains($0) }
            if hasNumber && markers >= 2 { return true }
        }
        guard text.digitCount > 0 || lower.contains("po box") else { return false }
        if !matches(unitNumber, in: text).isEmpty { return true }
        if Keywords.line(text, containsAnyOf: Keywords.latinAddress) { return true }
        let hasPostal = !matches(postalCode, in: text).isEmpty
        return hasPostal && (text.contains(",") || Keywords.line(text, containsAnyOf: Keywords.countries))
    }

    /// Adds lines next to a detected address ("Jalan Ampang", "Kuala Lumpur, Malaysia") to it.
    private func absorbAddressContinuations(addressLines: inout [Item], candidates: inout [Item]) {
        guard !addressLines.isEmpty else { return }
        var changed = true
        while changed {
            changed = false
            let addressIndices = Set(addressLines.map(\.index))
            if let i = candidates.firstIndex(where: { item in
                (addressIndices.contains(item.index - 1) || addressIndices.contains(item.index + 1))
                    && Self.looksLikeAddressContinuation(item.text)
            }) {
                addressLines.append(candidates.remove(at: i))
                changed = true
            }
        }
    }

    static func looksLikeAddressContinuation(_ text: String) -> Bool {
        if Keywords.line(text, containsAnyOf: Keywords.countries) { return true }
        if Keywords.line(text, containsAnyOf: Keywords.latinAddress) { return true }
        if !matches(postalCode, in: text).isEmpty { return true }
        if text.cjkCount > 0, text.filter({ Keywords.cjkAddress.contains($0) }).count >= 2 { return true }
        return text.contains(",") && text.digitCount > 0
    }

    // MARK: - Name

    /// Picks the person's name; returns true when the primary name is in CJK script.
    private func assignName(from candidates: inout [Item], domainStems: [String], japanese: Bool,
                            into draft: inout DraftContact) -> Bool {
        // Mixed-script lines ("陈美玲 Tan Mei Ling") become separate candidates sharing the line's position.
        var pool: [Item] = candidates.flatMap { item in
            item.text.splitByScript().map { Item(text: $0, index: item.index, relativeHeight: item.relativeHeight) }
        }

        let reading = pool.firstIndex { $0.text.isPureKana && $0.text.count <= 16 }.map { pool.remove(at: $0) }

        let latin = pool.filter { Self.isLatinNameShaped($0.text) && !Self.domainAffinity($0.text, stems: domainStems) }
            .map { item -> (item: Item, score: Double, affinity: Double) in
                let affinity = Self.emailAffinity(item.text, emails: draft.emails)
                return (item, Self.score(item, tokens: item.text.split(separator: " ").count, affinity: affinity), affinity)
            }
            .max { $0.score < $1.score }
        var cjk = pool.filter { Self.isCJKNameShaped($0.text) }
            .map { (item: $0, score: Self.score($0, tokens: 2, affinity: 0)) }
            .max { $0.score < $1.score }

        // On a mostly-Latin card, a small CJK phrase far from the name is a slogan, not a name.
        if let c = cjk, let l = latin, c.item.relativeHeight < 0.6, abs(c.item.index - l.item.index) > 2 {
            cjk = nil
        }

        let used = [latin?.item, cjk?.item, reading].compactMap { $0 }
        candidates.removeAll { candidate in used.contains { $0.index == candidate.index } }

        if let cjk {
            let parts = NameSplitter.split(cjk.item.text, japaneseContext: japanese)
            draft.givenName = parts.given
            draft.familyName = parts.family
            draft.confidence[.name] = min(0.8, parts.confidence)
            if let reading {
                setPhonetic(reading.text, into: &draft)
                if let latin { draft.nickname = latin.item.text; draft.confidence[.nickname] = 0.6 }
            } else if let latin {
                let latinParts = NameSplitter.split(latin.item.text, romanisedOfCJK: true)
                draft.phoneticGivenName = latinParts.given
                draft.phoneticFamilyName = latinParts.family
                draft.confidence[.phoneticName] = 0.6
            }
            return true
        }

        if let latin {
            let parts = NameSplitter.split(latin.item.text)
            draft.namePrefix = parts.prefix
            draft.givenName = parts.given
            draft.familyName = parts.family
            draft.nameSuffix = parts.suffix
            let base = latin.affinity >= 0.8 ? 0.95 : (latin.item.relativeHeight >= 0.7 ? 0.75 : 0.5)
            draft.confidence[.name] = min(base, parts.confidence + (latin.affinity >= 0.8 ? 0.2 : 0))
            if let reading { setPhonetic(reading.text, into: &draft) }
            return false
        }

        // No printed name found: guess from the email address ("jane.tan@" → "Jane Tan").
        if let email = draft.emails.first, let guess = Self.nameFromEmail(email) {
            let parts = NameSplitter.split(guess)
            draft.givenName = parts.given
            draft.familyName = parts.family
            draft.confidence[.name] = 0.3
        }
        return false
    }

    private func setPhonetic(_ reading: String, into draft: inout DraftContact) {
        let tokens = reading.split(separator: " ").map(String.init)
        if tokens.count >= 2 {
            draft.phoneticFamilyName = tokens[0]
            draft.phoneticGivenName = tokens[1...].joined()
            draft.confidence[.phoneticName] = 0.7
        } else {
            draft.phoneticFamilyName = reading
            draft.confidence[.phoneticName] = 0.4
        }
    }

    private static func score(_ item: Item, tokens: Int, affinity: Double) -> Double {
        var score = 1.0 + 1.5 * item.relativeHeight + 2.0 * affinity - 0.08 * Double(item.index)
        if (2...4).contains(tokens) { score += 0.3 }
        if tokens == 1 { score -= 0.6 }
        if item.text == item.text.lowercased() && item.text.latinCount > 0 { score -= 0.8 }
        return score
    }

    static func isLatinNameShaped(_ text: String) -> Bool {
        guard text.digitCount == 0, !text.contains("@"), text.cjkCount == 0, text.latinCount >= 3 else { return false }
        let name = text.split(separator: ",").first.map(String.init) ?? text
        let tokens = name.split(separator: " ")
        guard (1...5).contains(tokens.count) else { return false }
        let allowed = CharacterSet.letters.union(CharacterSet(charactersIn: ".'-’/"))
        return tokens.allSatisfy { token in
            token.unicodeScalars.allSatisfy { allowed.contains($0) }
                && (token.first!.isUppercase || Keywords.nameParticles.contains(token.lowercased())
                    || ["de", "van", "von", "der", "da", "di", "la", "le"].contains(token.lowercased()))
        }
    }

    static func isCJKNameShaped(_ text: String) -> Bool {
        guard text.isPureCJK, !text.isPureKana else { return false }
        let tokens = text.split(separator: " ")
        if tokens.count == 1 { return (2...5).contains(text.count) }
        return tokens.count == 2 && tokens.allSatisfy { (1...4).contains($0.count) }
    }

    /// 0...1: how well a printed name matches an email's local part.
    static func emailAffinity(_ name: String, emails: [String]) -> Double {
        let nameTokens = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 2 }
        guard !nameTokens.isEmpty else { return 0 }
        var best = 0.0
        for email in emails {
            guard let local = email.split(separator: "@").first.map({ String($0).lowercased() }) else { continue }
            let localTokens = local.split { !$0.isLetter }.map(String.init)
            if nameTokens.contains(where: localTokens.contains) { best = max(best, 1.0) }
            if nameTokens.contains(where: { $0.count >= 3 && local.contains($0) }) { best = max(best, 0.8) }
            for token in nameTokens {
                for other in nameTokens where other != token && local == String(token.prefix(1)) + other {
                    best = max(best, 0.9)
                }
            }
        }
        return best
    }

    static func nameFromEmail(_ email: String) -> String? {
        guard let local = email.split(separator: "@").first.map(String.init) else { return nil }
        let tokens = local.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 2 }
        guard (2...3).contains(tokens.count) else { return nil }
        let generic: Set<String> = ["info", "sales", "admin", "contact", "hello", "enquiry", "enquiries", "support", "office"]
        guard !tokens.contains(where: { generic.contains($0.lowercased()) }) else { return nil }
        return tokens.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }

    // MARK: - Company helpers

    private static let genericMailDomains: Set<String> = [
        "gmail", "googlemail", "yahoo", "hotmail", "outlook", "live", "icloud", "me", "mac", "msn", "aol", "qq",
        "163", "126", "naver", "daum", "hanmail", "singnet", "streamyx", "protonmail", "proton", "yandex",
    ]

    /// Distinctive part of each email/web domain: "jane@mail.acme.com.sg" → "acme".
    static func domainStems(emails: [String], urls: [String]) -> [String] {
        let hosts = emails.compactMap { $0.split(separator: "@").last.map(String.init) }
            + urls.map { url in
                var host = url.lowercased()
                if let scheme = host.range(of: "://") { host = String(host[scheme.upperBound...]) }
                return String(host.split(separator: "/").first ?? "")
            }
        var stems: [String] = []
        for host in hosts {
            var labels = host.lowercased().split(separator: ".").map(String.init)
            guard labels.count >= 2 else { continue }
            labels.removeLast()  // TLD
            if let last = labels.last, labels.count >= 2,
               ["com", "co", "net", "org", "edu", "gov", "ac", "or", "ne", "go"].contains(last) {
                labels.removeLast()
            }
            guard let stem = labels.last, stem.count >= 2, !genericMailDomains.contains(stem), !stems.contains(stem)
            else { continue }
            stems.append(stem)
        }
        return stems
    }

    static func domainAffinity(_ text: String, stems: [String]) -> Bool {
        let alnum = text.lowercased().filter { $0.isLetter || $0.isNumber }
        let words = text.split(separator: " ")
        let initials = String(words.compactMap(\.first)).lowercased()
        return stems.contains { stem in
            (stem.count >= 3 && alnum.contains(stem)) || (alnum.count >= 4 && stem.contains(alnum))
                || (words.count >= 2 && initials == stem)
        }
    }

    /// First line in the preferred script (CJK when the name is CJK), else the first line.
    private static func preferred(_ items: [Item], cjk: Bool) -> Item? {
        items.first { ($0.text.cjkCount > $0.text.latinCount) == cjk } ?? items.first
    }
}
