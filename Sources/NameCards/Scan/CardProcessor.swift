import CoreGraphics
import Foundation
import ImageIO
import NameCardsCore
import UniformTypeIdentifiers

/// Reads captured cards one at a time: on-device OCR and parsing, then Claude's labelling if enabled.
actor CardProcessor {
    struct Output {
        var result: CardReader.Result
        /// Set when Claude was enabled but couldn't be used; the on-device result is returned instead.
        var claudeError: String?
    }

    func read(_ image: CGImage, region: String, claudeKey: String?) async throws -> Output {
        var result = try await CardReader(parser: CardParser(region: region)).read(image)
        guard let claudeKey else { return Output(result: result) }
        do {
            let cardRegion = CardParser.inferRegion(from: result.draft.rawLines) ?? region
            let labelled = try await ClaudeParser(apiKey: claudeKey).parse(result.lines, region: cardRegion)
            result.draft = ClaudeParser.merge(rules: result.draft, claude: labelled)
            return Output(result: result)
        } catch {
            return Output(result: result, claudeError: error.localizedDescription)
        }
    }

    nonisolated static func save(_ image: CGImage, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    /// JPEG suitable for a contact photo.
    nonisolated static func photoData(from image: CGImage, maxDimension: Int = 800) -> Data? {
        let scale = min(1, Double(maxDimension) / Double(max(image.width, image.height)))
        let width = Int(Double(image.width) * scale), height = Int(Double(image.height) * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    nonisolated static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
