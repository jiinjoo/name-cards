import CoreImage
import Testing
@testable import NameCardsCore

@Suite struct CaptureGateTests {
    let quad = Quad(topLeft: CGPoint(x: 0.2, y: 0.8), topRight: CGPoint(x: 0.8, y: 0.8),
                    bottomRight: CGPoint(x: 0.8, y: 0.2), bottomLeft: CGPoint(x: 0.2, y: 0.2))

    func moved(_ dx: CGFloat) -> Quad {
        Quad(topLeft: CGPoint(x: 0.2 + dx, y: 0.8), topRight: CGPoint(x: 0.8 + dx, y: 0.8),
             bottomRight: CGPoint(x: 0.8 + dx, y: 0.2), bottomLeft: CGPoint(x: 0.2 + dx, y: 0.2))
    }

    /// Feeds frames at 10 fps and returns every decision.
    func run(_ gate: inout CaptureGate, _ frames: [(Quad?, Double)]) -> [CaptureGate.Decision] {
        frames.enumerated().map { i, frame in
            gate.process(.init(quad: frame.0, sharpness: frame.1, time: Double(i) * 0.1))
        }
    }

    @Test func capturesOnceWhenStillAndSharp() {
        var gate = CaptureGate()
        let decisions = run(&gate, Array(repeating: (quad, 200), count: 20))
        #expect(decisions.filter { $0 == .capture }.count == 1)
        #expect(decisions.firstIndex(of: .capture) == 6)
        #expect(decisions.last == .holding)
    }

    @Test func movingCardIsNotCaptured() {
        var gate = CaptureGate()
        let frames = (0..<20).map { i in (Optional(moved(CGFloat(i) * 0.03)), 200.0) }
        #expect(!run(&gate, frames).contains(.capture))
    }

    @Test func blurryCardCapturedAfterMaxWait() {
        var gate = CaptureGate()
        let decisions = run(&gate, Array(repeating: (quad, 10), count: 25))
        #expect(decisions.firstIndex(of: .capture) == 20)
    }

    @Test func briefDetectionDropoutDoesNotReset() {
        var gate = CaptureGate()
        var frames: [(Quad?, Double)] = Array(repeating: (quad, 200), count: 4)
        frames.append((nil, 0))
        frames += Array(repeating: (quad, 200), count: 4)
        #expect(run(&gate, frames).firstIndex(of: .capture) == 6)
    }

    @Test func rearmsAfterCardLeaves() {
        var gate = CaptureGate()
        var frames: [(Quad?, Double)] = Array(repeating: (quad, 200), count: 10)
        frames += Array(repeating: (nil, 0), count: 6)
        frames += Array(repeating: (quad, 200), count: 10)
        #expect(run(&gate, frames).filter { $0 == .capture }.count == 2)
    }

    @Test func sameCardHeldStaysCapturedOnce() {
        var gate = CaptureGate()
        var frames: [(Quad?, Double)] = Array(repeating: (quad, 200), count: 10)
        // A short occlusion (hand) shorter than absenceToRearm.
        frames += Array(repeating: (nil, 0), count: 3)
        frames += Array(repeating: (quad, 200), count: 20)
        #expect(run(&gate, frames).filter { $0 == .capture }.count == 1)
    }

    @Test func cardSlidInToReplaceIsCaptured() {
        var gate = CaptureGate()
        var frames: [(Quad?, Double)] = Array(repeating: (quad, 200), count: 10)
        frames += Array(repeating: (moved(0.3), 200), count: 10)
        #expect(run(&gate, frames).filter { $0 == .capture }.count == 2)
    }

    @Test func smallNudgeAfterCaptureIsIgnored() {
        var gate = CaptureGate()
        var frames: [(Quad?, Double)] = Array(repeating: (quad, 200), count: 10)
        frames += Array(repeating: (moved(0.04), 200), count: 10)
        #expect(run(&gate, frames).filter { $0 == .capture }.count == 1)
    }
}

@Suite struct CardImageTests {
    @Test func detectsAndFlattensATiltedCard() async throws {
        let scene = CIImage(cgImage: onDesk(renderCard(sampleCardRows), degrees: 12))
        let detector = CardDetector()
        let quad = try #require(detector.detect(in: scene))
        let crop = try #require(detector.crop(scene, to: quad))
        // The flattened crop should be card-shaped (1050×600 ≈ 1.75).
        let aspect = Double(crop.width) / Double(crop.height)
        #expect(abs(aspect - 1.75) < 0.15)

        let result = try await CardReader(parser: CardParser(region: "SG")).read(crop)
        #expect(result.draft.displayName == "Jane Tan")
        #expect(result.draft.emails == ["jane.tan@acmerobotics.com.sg"])
    }

    @Test func noCardOnEmptyDesk() {
        let empty = CIImage(color: CIColor(red: 0.15, green: 0.13, blue: 0.12))
            .cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(CardDetector().detect(in: empty) == nil)
    }

    @Test(arguments: [90, 180, 270])
    func readerRecoversRotatedCards(degrees: Int) async throws {
        let rotated = try #require(CardReader.rotate(renderCard(sampleCardRows), degrees: degrees))
        let result = try await CardReader(parser: CardParser(region: "SG")).read(rotated)
        #expect(result.draft.displayName == "Jane Tan")
        #expect(result.image.width > result.image.height)
    }

    @Test func sharpnessDropsWhenBlurred() async throws {
        let sharp = renderCard(sampleCardRows)
        let blurredImage = CIImage(cgImage: sharp).clampedToExtent()
            .applyingGaussianBlur(sigma: 6).cropped(to: CGRect(x: 0, y: 0, width: sharp.width, height: sharp.height))
        let blurred = try #require(CIContext().createCGImage(blurredImage, from: blurredImage.extent))
        let sharpScore = ImageMetrics.sharpness(of: sharp)
        let blurScore = ImageMetrics.sharpness(of: blurred)
        #expect(sharpScore > CaptureGate.Config().minSharpness)
        #expect(blurScore < CaptureGate.Config().minSharpness)
    }
}

@Suite struct SessionDeduperTests {
    func draft(_ name: String, org: String = "Acme", emails: [String] = [], phones: [Phone] = []) -> DraftContact {
        var d = DraftContact()
        let parts = name.split(separator: " ")
        d.givenName = String(parts.first ?? "")
        d.familyName = parts.dropFirst().joined(separator: " ")
        d.organization = org
        d.emails = emails
        d.phones = phones
        return d
    }

    @Test func sameEmailIsDuplicate() {
        let a = draft("Jane Tan", emails: ["Jane.Tan@acme.com"])
        let b = draft("Jane Tam", emails: ["jane.tan@acme.com"])
        #expect(SessionDeduper.duplicate(of: b, in: [a]) == a)
    }

    @Test func sameMobileIsDuplicate() {
        let a = draft("Jane Tan", phones: [Phone(number: "+6591234567", raw: "", kind: .mobile)])
        let b = draft("J Tan", phones: [Phone(number: "9123 4567", raw: "", kind: .mobile)])
        #expect(SessionDeduper.isSamePerson(a, b))
    }

    @Test func colleaguesSharingOfficeLineAreNotDuplicates() {
        let office = Phone(number: "+6561234567", raw: "", kind: .work)
        let a = draft("Jane Tan", emails: ["jane@acme.com"], phones: [office])
        let b = draft("Wei Ming Lim", emails: ["weiming@acme.com"], phones: [office])
        #expect(!SessionDeduper.isSamePerson(a, b))
    }

    @Test func sameNameAndCompanyIsDuplicate() {
        #expect(SessionDeduper.isSamePerson(draft("Jane Tan"), draft("jane tan")))
        #expect(!SessionDeduper.isSamePerson(draft("Jane Tan"), draft("Jane Tan", org: "Globex")))
    }
}
