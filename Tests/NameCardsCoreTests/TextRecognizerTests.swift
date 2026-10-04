import AppKit
import Testing
@testable import NameCardsCore

/// End-to-end: render a card with system fonts, run real Vision OCR, then parse.
/// Guards the recognizer's language strategy (Vision needs the card's CJK language listed first).
@Suite struct TextRecognizerTests {
    /// Rows are (text, point size); rendered top-down on a 1050×600 white card.
    static func render(_ rows: [(String, CGFloat)]) -> CGImage {
        let width = 1050, height = 600
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var y = CGFloat(height) - 50
        for (text, size) in rows {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            y -= size
            context.textPosition = CGPoint(x: 60, y: y)
            CTLineDraw(line, context)
            y -= size * 0.7
        }
        return context.makeImage()!
    }

    func scan(_ rows: [(String, CGFloat)]) throws -> DraftContact {
        CardParser(region: "SG").parse(try TextRecognizer().recognize(Self.render(rows)))
    }

    @Test func englishCard() throws {
        let draft = try scan([("Jane Tan", 44), ("Senior Product Manager", 26), ("Acme Robotics Pte Ltd", 28),
                              ("M +65 9123 4567", 24), ("jane.tan@acmerobotics.com.sg", 24)])
        #expect(draft.displayName == "Jane Tan")
        #expect(draft.organization == "Acme Robotics Pte Ltd")
        #expect(draft.phones.first?.number == "+6591234567")
        #expect(draft.emails == ["jane.tan@acmerobotics.com.sg"])
    }

    @Test func chineseCard() throws {
        let draft = try scan([("深圳市华星科技有限公司", 34), ("陈美玲", 48), ("手机：138 0013 8000", 24),
                              ("邮箱：meiling.tan@huaxingtech.cn", 24)])
        #expect(draft.familyName == "陈")
        #expect(draft.givenName == "美玲")
        #expect(draft.organization == "深圳市华星科技有限公司")
        #expect(draft.phones.first?.number == "+8613800138000")
        #expect(draft.emails == ["meiling.tan@huaxingtech.cn"])
    }

    @Test func japaneseCard() throws {
        let draft = try scan([("株式会社サクラデザイン", 32), ("山田 太郎", 48), ("携帯 090-1234-5678", 22),
                              ("yamada@sakura-design.co.jp", 22)])
        #expect(draft.familyName == "山田")
        #expect(draft.organization == "株式会社サクラデザイン")
        #expect(draft.phones.first == Phone(number: "+819012345678", raw: "090-1234-5678", kind: .mobile))
    }

    @Test func koreanCard() throws {
        let draft = try scan([("한빛소프트 주식회사", 32), ("김민준", 46), ("휴대폰 010-9876-5432", 22),
                              ("minjun.kim@hanbitsoft.co.kr", 22)])
        #expect(draft.familyName == "김")
        #expect(draft.givenName == "민준")
        #expect(draft.organization == "한빛소프트 주식회사")
        #expect(draft.phones.first?.kind == .mobile)
    }

    @Test func languageSelection() {
        #expect(TextRecognizer.preferredLanguages(for: ["Jane Tan"]) == nil)
        #expect(TextRecognizer.preferredLanguages(for: ["山田 太郎", "やまだ"])?.first == "ja-JP")
        #expect(TextRecognizer.preferredLanguages(for: ["김민준"])?.first == "ko-KR")
        #expect(TextRecognizer.preferredLanguages(for: ["陈美玲"])?.first == "zh-Hans")
    }
}
