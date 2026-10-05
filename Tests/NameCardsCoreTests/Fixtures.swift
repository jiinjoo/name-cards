import AppKit
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

let sampleCardRows: [(String, CGFloat)] = [
    ("Jane Tan", 44), ("Senior Product Manager", 26), ("Acme Robotics Pte Ltd", 28),
    ("M +65 9123 4567", 24), ("jane.tan@acmerobotics.com.sg", 24),
]

/// Renders (text, point size) rows top-down on a white 1050×600 card using system fonts.
func renderCard(_ rows: [(String, CGFloat)], width: Int = 1050, height: Int = 600) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(.white)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    var y = CGFloat(height) - 50
    for (text, size) in rows {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size),
                                                         .foregroundColor: NSColor.black]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        y -= size
        context.textPosition = CGPoint(x: 60, y: y)
        CTLineDraw(line, context)
        y -= size * 0.7
    }
    return context.makeImage()!
}

/// Places a card image on a dark "desk", rotated by `degrees`, as a camera would see it.
func onDesk(_ card: CGImage, degrees: CGFloat = 0, scale: CGFloat = 0.6, size: CGSize = CGSize(width: 1920, height: 1080)) -> CGImage {
    let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.15, green: 0.13, blue: 0.12, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    let width = size.width * scale
    let height = width * CGFloat(card.height) / CGFloat(card.width)
    context.translateBy(x: size.width / 2, y: size.height / 2)
    context.rotate(by: degrees * .pi / 180)
    context.draw(card, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
    return context.makeImage()!
}
