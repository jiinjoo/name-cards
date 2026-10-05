// nc-scan: run OCR + parsing on card images from the command line.
// Usage: swift run nc-scan [--region SG] [--lines] image...
import Foundation
import ImageIO
import NameCardsCore

var region = Locale.current.region?.identifier ?? "US"
var showLines = false
var paths: [String] = []
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--region": region = arguments.popFirst() ?? region
    case "--lines": showLines = true
    default: paths.append(argument)
    }
}
guard !paths.isEmpty else {
    print("usage: nc-scan [--region SG] [--lines] image...")
    exit(64)
}

let recognizer = TextRecognizer()
let parser = CardParser(region: region)
for path in paths {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        print("\(path): cannot read image")
        continue
    }
    let lines = try await recognizer.recognize(image)
    print("== \(path)")
    if showLines {
        for line in lines {
            print(String(format: "  [h %.3f c %.2f] %@", line.box.height, line.confidence, line.text))
        }
        print("--")
    }
    let draft = parser.parse(lines)
    func row(_ label: String, _ value: String, _ field: DraftContact.Field) {
        guard !value.isEmpty else { return }
        print("  \(label.padding(toLength: 12, withPad: " ", startingAt: 0)) \(value)  (\(String(format: "%.2f", draft.confidence(for: field))))")
    }
    row("prefix", draft.namePrefix, .name)
    row("given", draft.givenName, .name)
    row("family", draft.familyName, .name)
    row("suffix", draft.nameSuffix, .name)
    row("phonetic", [draft.phoneticGivenName, draft.phoneticFamilyName].filter { !$0.isEmpty }.joined(separator: " "), .phoneticName)
    row("nickname", draft.nickname, .nickname)
    row("title", draft.jobTitle, .jobTitle)
    row("department", draft.department, .department)
    row("company", draft.organization, .organization)
    for phone in draft.phones { row("phone", "\(phone.kind.rawValue): \(phone.number)  [\(phone.raw)]", .phones) }
    for email in draft.emails { row("email", email, .emails) }
    for url in draft.urls { row("url", url, .urls) }
    row("address", draft.address.replacingOccurrences(of: "\n", with: " / "), .address)
}
