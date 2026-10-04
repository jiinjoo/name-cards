import Foundation

/// Keyword tables used to classify card lines. Latin entries match whole words, case-insensitively;
/// CJK entries match as substrings.
enum Keywords {
    // MARK: Organisation

    /// Legal-entity suffixes: a line containing one of these is almost certainly the company.
    static let strongCompany = [
        "sdn bhd", "sdn. bhd.", "bhd", "berhad", "pte ltd", "pte. ltd.", "pte", "pty ltd", "ltd", "limited",
        "inc", "incorporated", "corp", "corporation", "llc", "llp", "plc", "gmbh", "co., ltd", "k.k.",
        "有限公司", "股份有限公司", "公司", "集团", "集團", "株式会社", "(株)", "有限会社", "合同会社",
        "주식회사", "(주)", "유한회사",
    ]

    /// Words that suggest an organisation but also appear in titles; only used when no title keyword matches.
    static let weakCompany = [
        "group", "holdings", "technologies", "technology", "solutions", "consulting", "consultancy", "partners",
        "bank", "university", "college", "enterprise", "enterprises", "industries", "associates", "studio",
        "studios", "labs", "agency", "ventures", "capital", "systems", "services", "international", "trading",
        "foundation", "institute", "hospital", "clinic", "firm", "media", "networks", "logistics",
        "银行", "銀行", "大学", "大學", "研究所", "事务所", "事務所", "医院", "醫院", "그룹", "은행", "대학교",
    ]

    // MARK: Person

    static let title = [
        "ceo", "cto", "cfo", "coo", "cmo", "cio", "cso", "cpo", "vp", "svp", "evp", "avp", "gm",
        "managing director", "founder", "co-founder", "cofounder", "director", "manager", "engineer",
        "president", "chairman", "chairwoman", "chairperson", "head", "lead", "officer", "executive",
        "consultant", "partner", "associate", "analyst", "specialist", "designer", "developer", "architect",
        "owner", "principal", "senior", "assistant", "coordinator", "advisor", "adviser", "representative",
        "secretary", "treasurer", "accountant", "counsel", "lawyer", "attorney", "advocate", "solicitor",
        "professor", "lecturer", "researcher", "scientist", "physician", "nurse", "supervisor",
        "administrator", "intern", "trainee", "strategist", "producer", "editor", "curator", "agent", "broker",
        "planner", "controller", "auditor", "programmer", "technician", "chief", "vice",
        "总经理", "總經理", "经理", "經理", "总监", "總監", "总裁", "總裁", "董事", "主席", "主任", "工程师",
        "工程師", "部长", "部長", "处长", "處長", "科长", "科長", "主管", "顾问", "顧問", "创始人", "創辦人",
        "创办人", "合伙人", "合夥人", "秘书", "秘書", "会计", "會計", "律师", "律師", "教授", "医生", "醫生",
        "专员", "專員", "助理", "社長", "会長", "會長", "課長", "係長", "取締役", "執行役員", "担当", "室長",
        "店長", "所長", "マネージャー", "マネジャー", "ディレクター", "エンジニア", "コンサルタント", "デザイナー",
        "대표", "이사", "상무", "전무", "부장", "차장", "과장", "대리", "팀장", "실장", "사원", "주임", "매니저",
        "엔지니어", "컨설턴트", "디자이너", "원장", "교수", "회장", "사장", "본부장", "연구원", "변호사",
    ]

    static let department = [
        "department", "dept", "division", "team", "unit of",
        "事业部", "事業部", "营业部", "営業部", "본부", "부서",
    ]

    /// CJK department names usually end in one of these characters (e.g. 市场部, 営業課, 마케팅팀).
    static let departmentSuffixes: [Character] = ["部", "課", "科", "處", "处", "팀", "실"]

    static let namePrefixes = [
        "mr", "mrs", "ms", "miss", "mdm", "madam", "dr", "prof", "ir", "ar", "tan sri", "puan sri", "datuk seri",
        "dato' sri", "dato sri", "datuk", "dato'", "dato", "datin", "tun", "haji", "hj", "hajah",
    ]

    static let nameSuffixes = [
        "phd", "ph.d", "ph.d.", "mba", "cpa", "cfa", "pe", "jr", "jr.", "sr", "sr.", "ii", "iii", "iv", "md", "esq",
        "acca", "fcca", "ca", "pmp", "cissp", "msc", "bsc", "ba", "ma", "frm",
    ]

    /// Patronymic particles in Malay and Tamil names: everything from the particle on is the family part.
    static let nameParticles = ["bin", "binti", "bt", "bte", "a/l", "a/p", "s/o", "d/o"]

    // MARK: Contact labels

    static let mobileLabels = [
        "mobile", "mob", "m", "hp", "h/p", "handphone", "cell", "c", "手机", "手機", "移动", "行動", "携帯",
        "휴대폰", "핸드폰", "휴대전화",
    ]
    static let faxLabels = ["fax", "f", "传真", "傳真", "팩스", "ファックス", "ファクス"]
    static let workLabels = [
        "tel", "tel.", "telephone", "phone", "t", "p", "o", "office", "direct", "d", "did", "dl", "work",
        "电话", "電話", "전화", "直通",
    ]
    static let mainLabels = ["main", "general", "hotline", "gen", "总机", "總機", "代表"]
    static let emailLabels = ["e", "email", "e-mail", "mail", "邮箱", "郵箱", "邮件", "電郵", "メール", "이메일"]
    static let webLabels = ["w", "web", "website", "url", "www", "网址", "網址", "网站", "網站", "ホームページ", "홈페이지"]
    static let addressLabels = ["address", "add", "addr", "a", "地址", "住所", "주소", "〒"]

    static var allLabels: [String] {
        mobileLabels + faxLabels + workLabels + mainLabels + emailLabels + webLabels + addressLabels
    }

    // MARK: Address

    static let latinAddress = [
        "street", "st", "st.", "road", "rd", "rd.", "jalan", "jln", "jln.", "avenue", "ave", "lane", "ln",
        "drive", "dr.", "boulevard", "blvd", "level", "lvl", "floor", "flr", "fl", "suite", "ste", "unit",
        "block", "blk", "tower", "building", "bldg", "lorong", "persiaran", "lebuh", "lebuhraya", "taman",
        "plaza", "place", "way", "highway", "centre", "center", "court", "crescent", "close", "industrial",
        "estate", "park", "square", "wisma", "menara", "bangunan", "jalan", "seksyen", "section", "po box",
    ]
    static let cjkAddress: [Character] = [
        "省", "市", "区", "區", "县", "縣", "路", "街", "道", "号", "號", "楼", "樓", "室", "厦", "廈", "都", "府",
        "県", "町", "村", "丁", "番", "階", "시", "구", "동", "로", "길", "층", "호",
    ]
    static let countries = [
        "malaysia", "singapore", "china", "hong kong", "taiwan", "japan", "korea", "south korea", "usa",
        "united states", "australia", "united kingdom", "uk", "indonesia", "thailand", "vietnam", "philippines",
        "india", "new zealand", "germany", "france", "canada", "中国", "中國", "香港", "台湾", "台灣", "日本",
        "한국", "대한민국", "新加坡", "马来西亚", "馬來西亞",
    ]

    // MARK: Matching

    /// Whole-word, case-insensitive match for Latin keywords; substring match for anything containing CJK.
    static func line(_ line: String, containsAnyOf keywords: [String]) -> Bool {
        let lower = line.lowercased()
        return keywords.contains { keyword in
            if keyword.cjkCount > 0 { return lower.contains(keyword) }
            return lower.containsWord(keyword)
        }
    }
}

extension String {
    /// Case-sensitive whole-word search; a "word boundary" is any non-letter, non-digit character.
    func containsWord(_ word: String) -> Bool {
        var searchRange = startIndex..<endIndex
        while let range = range(of: word, range: searchRange) {
            let beforeOK = range.lowerBound == startIndex || !self[index(before: range.lowerBound)].isWordCharacter
            let afterOK = range.upperBound == endIndex || !self[range.upperBound].isWordCharacter
            if beforeOK && afterOK { return true }
            searchRange = index(after: range.lowerBound)..<endIndex
        }
        return false
    }
}

extension Character {
    var isWordCharacter: Bool { isLetter || isNumber }
}
