import CoreGraphics
import Vision

/// On-device OCR via Apple Vision. Synchronous and CPU/ANE heavy: call it off the main actor.
///
/// Vision only reads CJK well when that language is listed *first*, and no single ordering handles
/// Chinese, Japanese and Korean together. So recognition runs in two passes: an auto-detect pass finds the
/// card's dominant script, then (for CJK cards) a second pass runs with that language first.
public struct TextRecognizer: Sendable {
    public init() {}

    /// Returns recognised lines sorted top-to-bottom, then left-to-right.
    public func recognize(_ image: CGImage) throws -> [OCRLine] {
        let detected = try run(on: image, languages: [], automatic: true)
        guard let languages = Self.preferredLanguages(for: detected.map(\.text)) else { return detected }
        return try run(on: image, languages: languages, automatic: false)
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

    private func run(on image: CGImage, languages: [String], automatic: Bool) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
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
