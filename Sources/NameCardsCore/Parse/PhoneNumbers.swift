import Foundation

/// Finds phone numbers in a card line, classifies them by their printed label and normalises them to E.164.
public enum PhoneNumbers {
    struct Region {
        let callingCode: String
        /// Whether national numbers are written with a leading trunk "0" that E.164 drops.
        let trunkZero: Bool
        /// Length of a national number written without a trunk prefix (only for regions without one).
        let nationalLength: Int?
        /// E.164 prefixes (after "+") that indicate a mobile number.
        let mobilePrefixes: [String]
    }

    static let regions: [String: Region] = [
        "SG": Region(callingCode: "65", trunkZero: false, nationalLength: 8, mobilePrefixes: ["658", "659"]),
        "MY": Region(callingCode: "60", trunkZero: true, nationalLength: nil, mobilePrefixes: ["601"]),
        "CN": Region(callingCode: "86", trunkZero: true, nationalLength: nil, mobilePrefixes: ["861"]),
        "HK": Region(callingCode: "852", trunkZero: false, nationalLength: 8, mobilePrefixes: ["8525", "8526", "8529"]),
        "MO": Region(callingCode: "853", trunkZero: false, nationalLength: 8, mobilePrefixes: ["8536"]),
        "TW": Region(callingCode: "886", trunkZero: true, nationalLength: nil, mobilePrefixes: ["8869"]),
        "JP": Region(callingCode: "81", trunkZero: true, nationalLength: nil, mobilePrefixes: ["8170", "8180", "8190"]),
        "KR": Region(callingCode: "82", trunkZero: true, nationalLength: nil, mobilePrefixes: ["8210"]),
        "US": Region(callingCode: "1", trunkZero: false, nationalLength: 10, mobilePrefixes: []),
        "CA": Region(callingCode: "1", trunkZero: false, nationalLength: 10, mobilePrefixes: []),
        "GB": Region(callingCode: "44", trunkZero: true, nationalLength: nil, mobilePrefixes: ["447"]),
        "AU": Region(callingCode: "61", trunkZero: true, nationalLength: nil, mobilePrefixes: ["614"]),
        "NZ": Region(callingCode: "64", trunkZero: true, nationalLength: nil, mobilePrefixes: ["642"]),
        "ID": Region(callingCode: "62", trunkZero: true, nationalLength: nil, mobilePrefixes: ["628"]),
        "TH": Region(callingCode: "66", trunkZero: true, nationalLength: nil, mobilePrefixes: ["666", "668", "669"]),
        "PH": Region(callingCode: "63", trunkZero: true, nationalLength: nil, mobilePrefixes: ["639"]),
        "VN": Region(callingCode: "84", trunkZero: true, nationalLength: nil, mobilePrefixes: ["843", "845", "847", "848", "849"]),
        "IN": Region(callingCode: "91", trunkZero: true, nationalLength: nil, mobilePrefixes: ["916", "917", "918", "919"]),
        "DE": Region(callingCode: "49", trunkZero: true, nationalLength: nil, mobilePrefixes: ["4915", "4916", "4917"]),
        "FR": Region(callingCode: "33", trunkZero: true, nationalLength: nil, mobilePrefixes: ["336", "337"]),
    ]

    /// Mobile prefixes for every known region, used when a number carries its own country code.
    private static let allMobilePrefixes = regions.values.flatMap(\.mobilePrefixes)

    // Starts with an optional "+" or "(", then a digit; allows spaces, dashes, dots and parentheses inside.
    private static let pattern = try! NSRegularExpression(pattern: #"(?:\+|\(\+?)?\d[\d \-.()]{5,}\d"#)

    struct Match {
        var phone: Phone
        let range: Range<String.Index>
        /// Whether the kind came from a printed label rather than the number's prefix.
        let labelled: Bool
    }

    /// All phone numbers in `line`, each labelled by the text that precedes it.
    static func find(in line: String, region: String) -> [Match] {
        let nsRange = NSRange(line.startIndex..., in: line)
        var matches: [Match] = []
        var previousEnd = line.startIndex
        for result in pattern.matches(in: line, range: nsRange) {
            guard let range = Range(result.range, in: line) else { continue }
            let raw = String(line[range]).trimmed
            let digits = raw.filter(\.isASCIIDigit)
            guard (7...15).contains(digits.count) else { continue }
            let preceding = String(line[previousEnd..<range.lowerBound])
            previousEnd = range.upperBound
            // Japanese postcodes look like short phone numbers: 〒150-0002.
            if preceding.trimmed.hasSuffix("〒") { continue }
            let number = normalize(raw, region: region)
            let label = kind(forPrecedingText: preceding)
            let phone = Phone(number: number ?? raw, raw: raw, kind: label ?? inferredKind(number))
            matches.append(Match(phone: phone, range: range, labelled: label != nil))
        }
        return matches
    }

    /// Normalises a printed number to E.164, or returns nil when the country can't be determined.
    public static func normalize(_ raw: String, region regionCode: String) -> String? {
        // "+44 (0)20 ..." style: the bracketed trunk zero is not dialled internationally.
        let cleaned = raw.replacingOccurrences(of: "(0)", with: "")
        let digits = cleaned.filter(\.isASCIIDigit)
        let hasPlus = cleaned.trimmed.hasPrefix("+") || cleaned.trimmed.hasPrefix("(+")
        guard (7...15).contains(digits.count) else { return nil }

        if hasPlus { return "+" + digits }
        if digits.hasPrefix("00") { return "+" + digits.dropFirst(2) }

        guard let region = regions[regionCode.uppercased()] else { return nil }
        if region.trunkZero, digits.hasPrefix("0") {
            return "+" + region.callingCode + digits.dropFirst()
        }
        if let length = region.nationalLength {
            if digits.count == length { return "+" + region.callingCode + digits }
            if digits.count == length + region.callingCode.count, digits.hasPrefix(region.callingCode) {
                return "+" + digits
            }
        }
        // Mainland Chinese mobiles are often printed without the trunk zero: 138 0013 8000.
        if regionCode.uppercased() == "CN", digits.count == 11, digits.hasPrefix("1") {
            return "+86" + digits
        }
        // A country code printed without "+", e.g. "60 12-345 6789".
        if digits.count >= 10, let code = regions.values.map(\.callingCode).first(where: { digits.hasPrefix($0) }),
           code.count >= 2 {
            return "+" + digits
        }
        return nil
    }

    /// Reads a label such as "M:", "Tel", "传真" at the end of `text` (i.e. immediately before a number).
    static func kind(forPrecedingText text: String) -> Phone.Kind? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)
            .union(.symbols).union(CharacterSet(charactersIn: "：|")))
        guard !lower.isEmpty else { return nil }
        let groups: [(Phone.Kind, [String])] = [
            (.mobile, Keywords.mobileLabels), (.fax, Keywords.faxLabels),
            (.main, Keywords.mainLabels), (.work, Keywords.workLabels),
        ]
        var best: (kind: Phone.Kind, length: Int)?
        for (kind, labels) in groups {
            for label in labels where lower.hasSuffix(label) {
                let start = lower.index(lower.endIndex, offsetBy: -label.count)
                // Latin labels must start at a word boundary ("tel" in "hotel" doesn't count).
                if label.cjkCount == 0, start != lower.startIndex, lower[lower.index(before: start)].isLetter {
                    continue
                }
                if label.count > (best?.length ?? 0) { best = (kind, label.count) }
            }
        }
        return best?.kind
    }

    /// Falls back to the number's prefix when no label was printed.
    static func inferredKind(_ e164: String?) -> Phone.Kind {
        guard let e164, e164.hasPrefix("+") else { return .work }
        let digits = e164.dropFirst()
        return allMobilePrefixes.contains { digits.hasPrefix($0) } ? .mobile : .work
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
