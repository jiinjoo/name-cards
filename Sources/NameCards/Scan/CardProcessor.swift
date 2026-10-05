import CoreGraphics
import Foundation
import ImageIO
import NameCardsCore
import UniformTypeIdentifiers

/// Reads captured cards one at a time and keeps a copy of each card image on disk.
actor CardProcessor {
    private var reader: CardReader

    /// ~/Library/Application Support/NameCards/Cards
    static let cardsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "NameCards/Cards", directoryHint: .isDirectory)
    }()

    init(region: String) {
        reader = CardReader(parser: CardParser(region: region))
    }

    func setRegion(_ region: String) {
        reader.parser.region = region
    }

    func read(_ image: CGImage, id: UUID) async throws -> (CardReader.Result, URL?) {
        let result = try await reader.read(image)
        return (result, Self.save(result.image, id: id))
    }

    private static func save(_ image: CGImage, id: UUID) -> URL? {
        try? FileManager.default.createDirectory(at: cardsDirectory, withIntermediateDirectories: true)
        let url = cardsDirectory.appending(path: "\(id.uuidString).jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? url : nil
    }
}
