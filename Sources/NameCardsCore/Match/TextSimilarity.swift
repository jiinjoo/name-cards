import Foundation

enum TextSimilarity {
    /// Jaro-Winkler similarity, 0...1.
    static func jaroWinkler(_ a: String, _ b: String) -> Double {
        let s = Array(a), t = Array(b)
        if s.isEmpty && t.isEmpty { return 1 }
        if s.isEmpty || t.isEmpty { return 0 }
        let window = max(0, max(s.count, t.count) / 2 - 1)
        var sMatched = [Bool](repeating: false, count: s.count)
        var tMatched = [Bool](repeating: false, count: t.count)
        var matches = 0
        for i in s.indices {
            let low = max(0, i - window), high = min(t.count - 1, i + window)
            guard low <= high else { continue }
            for j in low...high where !tMatched[j] && s[i] == t[j] {
                sMatched[i] = true
                tMatched[j] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0 }
        var transpositions = 0, k = 0
        for i in s.indices where sMatched[i] {
            while !tMatched[k] { k += 1 }
            if s[i] != t[k] { transpositions += 1 }
            k += 1
        }
        let m = Double(matches)
        let jaro = (m / Double(s.count) + m / Double(t.count) + (m - Double(transpositions) / 2) / m) / 3
        let prefix = zip(s, t).prefix(4).prefix { $0 == $1 }.count
        return jaro + Double(prefix) * 0.1 * (1 - jaro)
    }

    /// Lowercased, accent-folded, letters and digits only.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Both orders of a two-part name ("jane"+"tan" → "janetan", "tanjane"), normalised; empty parts skipped.
    static func nameKeys(given: String, family: String, others: [String] = []) -> [String] {
        var keys: [String] = []
        let g = normalized(given), f = normalized(family)
        if !g.isEmpty || !f.isEmpty {
            keys.append(g + f)
            if !g.isEmpty && !f.isEmpty { keys.append(f + g) }
        }
        keys += others.map(normalized).filter { !$0.isEmpty }
        return keys
    }

    /// Company names compared without legal suffixes ("Acme Pte Ltd" ≈ "ACME").
    static func companySimilarity(_ a: String, _ b: String) -> Double {
        let x = companyKey(a), y = companyKey(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        if x == y { return 1 }
        if (x.count >= 4 && y.contains(x)) || (y.count >= 4 && x.contains(y)) { return 0.9 }
        return jaroWinkler(x, y)
    }

    static func companyKey(_ name: String) -> String {
        var lower = " " + name.lowercased() + " "
        for suffix in Keywords.strongCompany.sorted(by: { $0.count > $1.count }) {
            lower = lower.replacingOccurrences(of: suffix.cjkCount > 0 ? suffix : " \(suffix) ", with: " ")
        }
        return normalized(lower)
    }
}
