import CoreGraphics
import Foundation
import Vision

/// On-device OCR via Apple Vision.
///
/// Vision only reads CJK well when that language is listed *first*, and no single ordering handles
/// Chinese, Japanese and Korean together. So recognition runs in two passes: an auto-detect pass finds the
/// card's dominant script, then (for CJK cards) a second pass runs with that language first.
public struct TextRecognizer: Sendable {
    /// Vision blocks its calling thread and, on macOS 26, can deadlock when every Swift-concurrency pool
    /// thread is blocked inside it. All recognition therefore runs on this private serial queue, which
    /// also keeps OCR to one card at a time.
    private static let queue = DispatchQueue(label: "namecards.ocr", qos: .userInitiated)

    public init() {}

    /// Returns recognised lines sorted top-to-bottom, then left-to-right.
    public func recognize(_ image: CGImage) async throws -> [OCRLine] {
        try await onQueue {
            let detected = try run(on: image, languages: [], automatic: true)
            guard let languages = Self.preferredLanguages(for: detected.map(\.text)) else { return detected }
            return try run(on: image, languages: languages, automatic: false)
        }
    }

    /// A single fast, auto-detecting pass; only good enough to compare orientations.
    func recognizeQuickly(_ image: CGImage) async throws -> [OCRLine] {
        try await onQueue { try run(on: image, languages: [], automatic: true, level: .fast) }
    }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async { continuation.resume(with: Result(catching: work)) }
        }
    }

    /// Language order for the second pass, or nil when the card is Latin-only.
    static func preferredLanguages(for texts: [String]) -> [String]? {
        let text = texts.joined()
        if text.containsKana || text.contains("株式会社") || text.contains("〒") {
            return ["ja-JP", "en-US"]
        }
        if text.containsHangul { return ["ko-KR", "en-US"] }
        // Simplified-first also reads Traditional characters correctly.
        if text.count(of: .han) >= 2 { return ["zh-Hans", "zh-Hant", "en-US"] }
        return nil
    }

    private func run(on image: CGImage, languages: [String], automatic: Bool,
                     level: VNRequestTextRecognitionLevel = .accurate) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = automatic
        if !languages.isEmpty { request.recognitionLanguages = languages }
        try VNImageRequestHandler(cgImage: image).perform([request])

        let lines = (request.results ?? []).compactMap { observation -> OCRLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return OCRLine(text: candidate.string, box: observation.boundingBox, confidence: candidate.confidence)
        }
        return lines.sorted { a, b in
            // Treat lines whose vertical centres are within half a line height as the same row.
            if abs(a.box.midY - b.box.midY) < min(a.box.height, b.box.height) / 2 {
                return a.box.minX < b.box.minX
            }
            return a.box.midY > b.box.midY
        }
    }
}
