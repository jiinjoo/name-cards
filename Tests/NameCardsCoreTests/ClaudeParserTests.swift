import Foundation
import Testing
@testable import NameCardsCore

@Suite struct ClaudeParserTests {
    func response(_ fields: [String: Any], stopReason: String = "end_turn") throws -> Data {
        let text = String(data: try JSONSerialization.data(withJSONObject: fields), encoding: .utf8)!
        return try JSONSerialization.data(withJSONObject: [
            "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": text]],
            "stop_reason": stopReason,
        ])
    }

    var fields: [String: Any] {
        [
            "namePrefix": "", "givenName": "美玲", "familyName": "陈", "nameSuffix": "",
            "phoneticGivenName": "Mei Ling", "phoneticFamilyName": "Tan", "nickname": "",
            "jobTitle": "总监", "department": "市场部", "organization": "深圳市华星科技有限公司",
            "phones": [["number": "138 0013 8000", "kind": "mobile"], ["number": "+86 755 8888 6666", "kind": "work"]],
            "emails": ["MeiLing.Tan@huaxingtech.cn"], "urls": [], "address": "深圳市南山区科技园路1号",
            "uncertainFields": ["department"],
        ]
    }

    @Test func requestSendsOnlyTextWithSchemaAndFallback() throws {
        let lines = card([("陈美玲", 0.08), ("手机：138 0013 8000", 0.04)])
        let body = try JSONSerialization.jsonObject(with: ClaudeParser.requestBody(lines: lines, region: "SG")) as! [String: Any]
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["fallbacks"] as? String == "default")
        let config = body["output_config"] as! [String: Any]
        #expect(config["effort"] as? String == "low")
        let format = config["format"] as! [String: Any]
        #expect(format["type"] as? String == "json_schema")
        let schema = format["schema"] as! [String: Any]
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect((schema["required"] as! [String]).count == (schema["properties"] as! [String: Any]).count)
        let content = ((body["messages"] as! [[String: Any]])[0]["content"] as! String)
        #expect(content.contains("Default region: SG"))
        #expect(content.contains("[1.00] 陈美玲"))
        #expect(content.contains("[0.50] 手机：138 0013 8000"))
    }

    @Test func decodesFieldsSkippingThinkingBlocks() throws {
        let draft = try ClaudeParser.draft(fromResponse: response(fields), region: "CN")
        #expect(draft.familyName == "陈")
        #expect(draft.phoneticGivenName == "Mei Ling")
        #expect(draft.phones == [
            Phone(number: "+8613800138000", raw: "138 0013 8000", kind: .mobile),
            Phone(number: "+8675588886666", raw: "+86 755 8888 6666", kind: .work),
        ])
        #expect(draft.emails == ["meiling.tan@huaxingtech.cn"])
        #expect(draft.confidence(for: .department) == 0.5)
        #expect(draft.confidence(for: .name) == 0.9)
        #expect(draft.confidence(for: .urls) == 0)
    }

    @Test func refusalAndTruncationAreErrors() throws {
        #expect(throws: ClaudeParser.ParserError.refusal) {
            try ClaudeParser.draft(fromResponse: response([:], stopReason: "refusal"), region: "SG")
        }
        #expect(throws: ClaudeParser.ParserError.truncated) {
            try ClaudeParser.draft(fromResponse: response([:], stopReason: "max_tokens"), region: "SG")
        }
    }

    @Test func apiErrorMessageIsExtracted() {
        let data = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.data(using: .utf8)!
        #expect(ClaudeParser.errorMessage(in: data) == "invalid x-api-key")
    }

    @Test func mergeKeepsClaudeLabelsAndOnDeviceExtras() throws {
        let rules = parse([("陈美玲", 0.083), ("Tan Mei Ling", 0.047), ("T +86 755 8888 6666", 0.04),
                           ("Fax +86 755 8888 6667", 0.04), ("www.huaxingtech.cn", 0.04)], region: "CN")
        var claude = try ClaudeParser.draft(fromResponse: response(fields), region: "CN")
        claude.address = ""
        let merged = ClaudeParser.merge(rules: rules, claude: claude)
        #expect(merged.id == rules.id)
        #expect(merged.rawLines == rules.rawLines)
        #expect(merged.department == "市场部")
        // The fax only the on-device parser found is kept; the shared work number isn't duplicated.
        #expect(merged.phones.map(\.kind) == [.mobile, .work, .fax])
        #expect(merged.urls == ["www.huaxingtech.cn"])
    }

    @Test func missingKeyFailsFast() async {
        await #expect(throws: ClaudeParser.ParserError.missingAPIKey) {
            try await ClaudeParser(apiKey: " ").parse([], region: "SG")
        }
    }
}
