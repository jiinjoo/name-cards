import CoreGraphics
@testable import NameCardsCore

/// Builds OCR lines top-to-bottom from (text, relative font height) pairs, as Vision would return them.
func card(_ rows: [(String, CGFloat)]) -> [OCRLine] {
    var y: CGFloat = 0.95
    return rows.map { text, height in
        defer { y -= height + 0.02 }
        return OCRLine(text: text, box: CGRect(x: 0.05, y: y - height, width: 0.6, height: height))
    }
}

func parse(_ rows: [(String, CGFloat)], region: String = "SG") -> DraftContact {
    CardParser(region: region).parse(card(rows))
}
