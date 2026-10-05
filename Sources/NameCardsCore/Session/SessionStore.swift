import Foundation

/// Persists the scanning session (card records as JSON plus card images) so nothing is lost if the app quits
/// mid-event.
public struct SessionStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// ~/Library/Application Support/NameCards
    public static var standard: SessionStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SessionStore(directory: base.appending(path: "NameCards", directoryHint: .isDirectory))
    }

    public var fileURL: URL { directory.appending(path: "session.json") }
    public var imagesDirectory: URL { directory.appending(path: "Cards", directoryHint: .isDirectory) }

    public func imageURL(for record: CardRecord) -> URL {
        imagesDirectory.appending(path: record.imageFileName)
    }

    private struct Snapshot: Codable {
        var version = 1
        var cards: [CardRecord]
    }

    /// Saved records, oldest first; empty if there is no session yet.
    public func load() throws -> [CardRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode(Snapshot.self, from: data).cards
    }

    public func save(_ records: [CardRecord]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(Snapshot(cards: records))
        try data.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
