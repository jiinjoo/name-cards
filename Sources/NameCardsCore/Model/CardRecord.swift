import Foundation

/// One captured card and where it is in the review flow. Persisted in the session file.
public struct CardRecord: Identifiable, Hashable, Codable, Sendable {
    public enum Status: Hashable, Codable, Sendable {
        /// OCR hasn't finished (re-run on next launch if the app quit mid-read).
        case reading
        case ready
        case failed(String)
    }

    public enum Review: String, CaseIterable, Hashable, Codable, Sendable {
        case pending, approved, skipped
    }

    public let id: UUID
    public var capturedAt: Date
    /// "Met at" label active when the card was scanned.
    public var eventName: String
    /// File name inside the session's image directory.
    public var imageFileName: String
    public var draft: DraftContact?
    public var status: Status
    public var review: Review

    public init(id: UUID = UUID(), capturedAt: Date = Date(), eventName: String = "", draft: DraftContact? = nil,
                status: Status = .reading, review: Review = .pending) {
        self.id = id
        self.capturedAt = capturedAt
        self.eventName = eventName
        self.imageFileName = "\(id.uuidString).jpg"
        self.draft = draft
        self.status = status
        self.review = review
    }
}
