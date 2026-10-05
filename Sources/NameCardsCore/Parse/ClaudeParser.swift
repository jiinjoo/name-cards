import Foundation

/// Optional field labelling by Claude. Sends only the OCR text lines (never the card image) and gets back
/// contact fields as schema-constrained JSON. Off by default; the user opts in and supplies an API key.
public struct ClaudeParser: Sendable {
    public static let model = "claude-opus-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public enum ParserError: LocalizedError, Equatable {
        case missingAPIKey
        case http(status: Int, message: String)
        case refusal
        case truncated
        case invalidResponse(String)

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey: "No Claude API key is set. Add one in Settings."
            case .http(let status, let message): "Claude API error \(status): \(message)"
            case .refusal: "Claude declined to read this card."
            case .truncated: "Claude's answer was cut off."
            case .invalidResponse(let detail): "Unexpected response from Claude: \(detail)"
            }
        }
    }

    public var apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Labels the card's OCR lines. `region` is the fallback country for phone numbers.
    public func parse(_ lines: [OCRLine], region: String) async throws -> DraftContact {
        guard !apiKey.trimmed.isEmpty else { throw ParserError.missingAPIKey }
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey.trimmed, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Lets the API re-run a declined request on Anthropic's recommended fallback model.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try Self.requestBody(lines: lines, region: region)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ParserError.http(status: status, message: Self.errorMessage(in: data))
        }
        return try Self.draft(fromResponse: data, region: region)
    }

    // MARK: Request

    static let systemPrompt = """
    You turn the OCR text of one business card into contact fields. The lines are in reading order, top \
    to bottom, each with its relative font size (1.0 = the largest text on the card). OCR may contain small \
    errors; fix obvious ones (e.g. "0" for "O" in an email domain) but never invent information that isn't \
    on the card. Leave a field as an empty string or empty array when the card doesn't show it.

    Conventions:
    - The person's name, not the company's. Split it into given and family name in the order the culture \
      uses (Chinese, Japanese and Korean names: family name first on the card; romanised Chinese names like \
      "Tan Mei Ling" are usually family-first too). Honorifics (Dr., Datuk, Mr.) go in namePrefix; \
      credentials (PhD, CPA) go in nameSuffix. Malay patronymics keep "bin"/"binti" in the family name.
    - When the card prints the name in a CJK script and also in Latin letters, the CJK name is the main \
      name and the Latin rendering goes in the phonetic fields. A kana reading (furigana) also goes in the \
      phonetic fields; in that case put a Latin rendering, if any, in nickname.
    - Keep text in the script printed on the card; don't translate. Prefer the language of the person's \
      name when a job title or company is printed in two languages.
    - Phone numbers in E.164 (e.g. +6591234567). Work out the country from the card (address, email \
      domain, prefix); if the card doesn't reveal it, use the default region given. Label each one mobile, \
      work, fax, main or other from the card's labels or the number's format.
    - Emails in lowercase. Websites as printed, without a trailing slash.
    - address: the full postal address as printed, one card line per line, separated by "\\n".
    - uncertainFields: list every field whose value you had to guess or that the OCR made ambiguous.
    """

    /// Every property is required (empty when absent) and no extras are allowed, as structured outputs requires.
    static var schema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let fieldNames = DraftContact.Field.allCases.map(\.rawValue)
        let properties: [String: Any] = [
            "namePrefix": string, "givenName": string, "familyName": string, "nameSuffix": string,
            "phoneticGivenName": string, "phoneticFamilyName": string, "nickname": string,
            "jobTitle": string, "department": string, "organization": string,
            "phones": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "number": string,
                        "kind": ["type": "string", "enum": Phone.Kind.allCases.map(\.rawValue)],
                    ],
                    "required": ["number", "kind"],
                    "additionalProperties": false,
                ] as [String: Any],
            ] as [String: Any],
            "emails": ["type": "array", "items": string],
            "urls": ["type": "array", "items": string],
            "address": string,
            "uncertainFields": ["type": "array", "items": ["type": "string", "enum": fieldNames]],
        ]
        return [
            "type": "object",
            "properties": properties,
            "required": Array(properties.keys).sorted(),
            "additionalProperties": false,
        ]
    }

    static func requestBody(lines: [OCRLine], region: String) throws -> Data {
        let maxHeight = max(lines.map(\.box.height).max() ?? 1, 0.0001)
        let cardText = lines.map { line in
            String(format: "[%.2f] %@", Double(line.box.height / maxHeight), line.text)
        }.joined(separator: "\n")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "fallbacks": "default",
            // Field labelling is a simple extraction task; low effort keeps it quick.
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": schema],
            ] as [String: Any],
            "system": systemPrompt,
            "messages": [[
                "role": "user",
                "content": "Default region: \(region)\n\nCard text:\n\(cardText)",
            ]],
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    // MARK: Response

    private struct Response: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stop_reason: String?
    }

    private struct Fields: Decodable {
        struct PhoneField: Decodable {
            let number: String
            let kind: String
        }
        let namePrefix, givenName, familyName, nameSuffix: String
        let phoneticGivenName, phoneticFamilyName, nickname: String
        let jobTitle, department, organization: String
        let phones: [PhoneField]
        let emails, urls: [String]
        let address: String
        let uncertainFields: [String]
    }

    static func draft(fromResponse data: Data, region: String) throws -> DraftContact {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ParserError.invalidResponse("couldn't decode the message")
        }
        switch response.stop_reason {
        case "refusal": throw ParserError.refusal
        case "max_tokens": throw ParserError.truncated
        default: break
        }
        guard let text = response.content.last(where: { $0.type == "text" })?.text,
              let json = text.data(using: .utf8) else {
            throw ParserError.invalidResponse("no text in the reply")
        }
        let fields: Fields
        do {
            fields = try JSONDecoder().decode(Fields.self, from: json)
        } catch {
            throw ParserError.invalidResponse("the fields didn't match the schema")
        }

        var draft = DraftContact()
        draft.namePrefix = fields.namePrefix.trimmed
        draft.givenName = fields.givenName.trimmed
        draft.familyName = fields.familyName.trimmed
        draft.nameSuffix = fields.nameSuffix.trimmed
        draft.phoneticGivenName = fields.phoneticGivenName.trimmed
        draft.phoneticFamilyName = fields.phoneticFamilyName.trimmed
        draft.nickname = fields.nickname.trimmed
        draft.jobTitle = fields.jobTitle.trimmed
        draft.department = fields.department.trimmed
        draft.organization = fields.organization.trimmed
        draft.phones = fields.phones.compactMap { field in
            let raw = field.number.trimmed
            guard !raw.isEmpty else { return nil }
            let number = raw.hasPrefix("+") ? "+" + raw.filter(\.isASCIIDigit)
                : PhoneNumbers.normalize(raw, region: region) ?? raw
            return Phone(number: number, raw: raw, kind: Phone.Kind(rawValue: field.kind) ?? .other)
        }
        draft.emails = fields.emails.map { $0.trimmed.lowercased() }.filter { !$0.isEmpty }
        draft.urls = fields.urls.map(\.trimmed).filter { !$0.isEmpty }
        draft.address = fields.address.trimmed

        let uncertain = Set(fields.uncertainFields.compactMap(DraftContact.Field.init(rawValue:)))
        for field in DraftContact.Field.allCases where draft.hasValue(field) {
            draft.confidence[field] = uncertain.contains(field) ? 0.5 : 0.9
        }
        return draft
    }

    static func errorMessage(in data: Data) -> String {
        struct ErrorBody: Decodable {
            struct Detail: Decodable { let message: String }
            let error: Detail
        }
        return (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
            ?? String(data: data, encoding: .utf8)?.prefix(200).description ?? "no details"
    }

    // MARK: Merge

    /// Claude's labelling wins for single-value fields; list fields are combined so a phone or email the
    /// on-device parser found is never lost. Raw OCR lines come from the on-device read.
    public static func merge(rules: DraftContact, claude: DraftContact) -> DraftContact {
        var merged = claude
        merged.id = rules.id
        merged.rawLines = rules.rawLines
        let singles: [(WritableKeyPath<DraftContact, String>, DraftContact.Field)] = [
            (\.jobTitle, .jobTitle), (\.department, .department), (\.organization, .organization),
            (\.nickname, .nickname), (\.address, .address),
        ]
        for (keyPath, field) in singles where merged[keyPath: keyPath].isEmpty && !rules[keyPath: keyPath].isEmpty {
            merged[keyPath: keyPath] = rules[keyPath: keyPath]
            merged.confidence[field] = rules.confidence[field]
        }
        if !merged.hasValue(.name) && rules.hasValue(.name) {
            merged.namePrefix = rules.namePrefix
            merged.givenName = rules.givenName
            merged.familyName = rules.familyName
            merged.nameSuffix = rules.nameSuffix
            merged.confidence[.name] = rules.confidence[.name]
        }
        for phone in rules.phones where !merged.phones.contains(where: { $0.comparable == phone.comparable }) {
            merged.phones.append(phone)
        }
        for email in rules.emails where !merged.emails.contains(email) { merged.emails.append(email) }
        for url in rules.urls where !merged.urls.contains(where: { $0.caseInsensitiveCompare(url) == .orderedSame }) {
            merged.urls.append(url)
        }
        return merged
    }
}

extension DraftContact {
    func hasValue(_ field: Field) -> Bool {
        switch field {
        case .name: !givenName.isEmpty || !familyName.isEmpty
        case .phoneticName: !phoneticGivenName.isEmpty || !phoneticFamilyName.isEmpty
        case .nickname: !nickname.isEmpty
        case .jobTitle: !jobTitle.isEmpty
        case .department: !department.isEmpty
        case .organization: !organization.isEmpty
        case .phones: !phones.isEmpty
        case .emails: !emails.isEmpty
        case .urls: !urls.isEmpty
        case .address: !address.isEmpty
        }
    }
}
