import CoreGraphics
import Foundation
import ImageIO
import NameCardsCore
import UniformTypeIdentifiers

/// Reads captured cards one at a time.
actor CardProcessor {
    private var reader: CardReader

    init(region: String) {
        reader = CardReader(parser: CardParser(region: region))
    }

    func read(_ image: CGImage) async throws -> CardReader.Result {
        try await reader.read(image)
    }

    nonisolated static func save(_ image: CGImage, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    nonisolated static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
