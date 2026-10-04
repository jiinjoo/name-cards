import Foundation

/// Writing-system helpers for mixed Latin/CJK business cards.
enum Script: Equatable {
    case han, kana, hangul, latin, digit, other

    init(_ scalar: Unicode.Scalar) {
        switch scalar.value {
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: self = .kana
        case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F: self = .hangul
        case 0x30...0x39: self = .digit
        default:
            if scalar.properties.isIdeographic {
                self = .han
            } else if scalar.properties.isAlphabetic && scalar.value < 0x0250 {
                self = .latin
            } else {
                self = .other
            }
        }
    }

    var isCJK: Bool { self == .han || self == .kana || self == .hangul }
}

extension String {
    func count(of script: Script) -> Int { unicodeScalars.filter { Script($0) == script }.count }

    var cjkCount: Int { unicodeScalars.filter { Script($0).isCJK }.count }
    var latinCount: Int { count(of: .latin) }
    var digitCount: Int { count(of: .digit) }
    var containsKana: Bool { unicodeScalars.contains { Script($0) == .kana } }
    var containsHangul: Bool { unicodeScalars.contains { Script($0) == .hangul } }

    /// True when every non-space scalar is CJK (han, kana or hangul).
    var isPureCJK: Bool {
        let scalars = unicodeScalars.filter { !$0.properties.isWhitespace }
        return !scalars.isEmpty && scalars.allSatisfy { Script($0).isCJK }
    }

    var isPureKana: Bool {
        let scalars = unicodeScalars.filter { !$0.properties.isWhitespace && $0 != "・" }
        return !scalars.isEmpty && scalars.allSatisfy { Script($0) == .kana }
    }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Collapses internal runs of whitespace to single spaces.
    var collapsingWhitespace: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Splits a line like "陈美玲 Tan Mei Ling" into its CJK and Latin runs.
    /// Returns `[self]` unless the line clearly mixes both scripts.
    func splitByScript() -> [String] {
        guard cjkCount >= 2, latinCount >= 2 else { return [self] }
        var runs: [(isCJK: Bool, text: String)] = []
        for character in self {
            guard let scalar = character.unicodeScalars.first else { continue }
            let script = Script(scalar)
            let isCJK: Bool
            switch script {
            case .han, .kana, .hangul: isCJK = true
            case .latin, .digit: isCJK = false
            case .other:
                // Spaces and punctuation stay with the current run.
                if runs.isEmpty { continue }
                runs[runs.count - 1].text.append(character)
                continue
            }
            if let last = runs.last, last.isCJK == isCJK {
                runs[runs.count - 1].text.append(character)
            } else {
                runs.append((isCJK, String(character)))
            }
        }
        let parts = runs.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [self] : parts
    }
}
