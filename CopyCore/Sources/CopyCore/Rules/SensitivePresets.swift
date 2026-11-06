import Foundation

/// 内置的敏感内容识别。每一项都在正则之外加了校验, 用来压低误报。
public enum SensitivePreset: String, Codable, CaseIterable, Hashable, Sendable {
    /// API key、访问令牌、私钥: `sk-`、`ghp_`/`gho_`/`github_pat_`、`AKIA`、`xox[bp]-`、
    /// `AIza`、PEM 私钥头、JWT。
    case secrets
    /// 银行卡号: 13–19 位 (可带空格或连字符), 卡组织号段 + Luhn 校验。
    case bankCard
    /// 中国居民身份证号: 18 位, 出生日期合法 + 末位校验码。
    case chineseID
    /// 短信验证码: 来自「信息」app 的 4–8 位纯数字, 或短文本里同时出现「验证码 / code」
    /// 等字样和 4–8 位数字。
    case verificationCode
}

/// 在时间预算内跑正则。`NSRegularExpression` 没有超时参数; `.reportProgress` 让它在
/// 匹配过程中定期回调 (实测灾难回溯的 `(a+)+$` 也会回调), 回调里超过截止时间就叫停。
struct BudgetedRegex: @unchecked Sendable { // NSRegularExpression 编译后不可变、线程安全
    let regex: NSRegularExpression

    enum Result: Equatable { case matched, notMatched, timedOut }

    func firstMatch(in text: NSString, deadline: Date) -> (Result, NSRange?) {
        var found: NSRange?
        var timedOut = false
        regex.enumerateMatches(in: text as String, options: [.reportProgress],
                               range: NSRange(location: 0, length: text.length)) { match, flags, stop in
            if let match {
                found = match.range
                stop.pointee = true
            } else if flags.contains(.progress), Date() > deadline {
                timedOut = true
                stop.pointee = true
            }
        }
        if found != nil { return (.matched, found) }
        return (timedOut ? .timedOut : .notMatched, nil)
    }

    /// 逐个匹配, `accept` 返回 true 即停 (用于正则粗筛 + 校验位精筛)。
    func firstMatch(in text: NSString, deadline: Date, where accept: (String) -> Bool) -> Result {
        var result = Result.notMatched
        regex.enumerateMatches(in: text as String, options: [.reportProgress],
                               range: NSRange(location: 0, length: text.length)) { match, flags, stop in
            if let match {
                if accept(text.substring(with: match.range)) { result = .matched; stop.pointee = true }
                else if Date() > deadline { result = .timedOut; stop.pointee = true }
            } else if flags.contains(.progress), Date() > deadline {
                result = .timedOut
                stop.pointee = true
            }
        }
        return result
    }
}

/// 预设的识别逻辑。正则在 `CaptureEvaluator` 里编译一次后复用。
enum SensitiveDetector {
    static let secretPatterns: [String] = [
        #"\bsk-(?:proj-|ant-)?[A-Za-z0-9_\-]{20,}"#,              // OpenAI / Anthropic 等
        #"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}"#,           // GitHub 令牌
        #"\bgithub_pat_[A-Za-z0-9_]{60,}"#,                       // GitHub 细粒度令牌
        #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#,                        // AWS access key
        #"\bxox[abposr]-[A-Za-z0-9-]{10,}"#,                      // Slack
        #"\bAIza[0-9A-Za-z_\-]{35}\b"#,                           // Google API key
        #"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----"#,              // PEM 私钥
        #"\beyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#, // JWT
    ]
    /// 13–19 位数字, 中间可以有单个空格或连字符; 前后不能紧挨数字。
    static let cardPattern = #"(?<![0-9])[0-9](?:[ \-]?[0-9]){12,18}(?![0-9])"#
    static let idPattern = #"(?<![0-9])[1-9][0-9]{5}(?:18|19|20)[0-9]{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])[0-9]{3}[0-9Xx](?![0-9A-Za-z])"#
    static let codeKeywordPattern = #"(?i)验证码|校验码|动态码|动态密码|verification code|security code|one-time (?:pass)?code|\bOTP\b|\b2FA\b"#
    static let codeDigitsPattern = #"(?<![0-9])[0-9]{4,8}(?![0-9])"#
    /// 「信息」app。
    static let messagesBundleID = "com.apple.MobileSMS"
    /// 验证码规则只看这么长以内的文本: 短信本身很短, 长文里碰巧有这些字样不算。
    static let codeTextLimit = 300

    static func isValidCard(_ raw: String) -> Bool {
        let digits = raw.compactMap { $0.wholeNumberValue }
        guard (13...19).contains(digits.count), luhn(digits) else { return false }
        let s = String(raw.filter(\.isNumber))
        func prefix(_ n: Int) -> Int { Int(s.prefix(n)) ?? -1 }
        switch digits.count {
        case 13: return s.hasPrefix("4")
        case 14: return (300...305).contains(prefix(3)) || s.hasPrefix("36") || s.hasPrefix("38")
        case 15: return s.hasPrefix("34") || s.hasPrefix("37")
        default:
            return s.hasPrefix("4")                                   // Visa
                || (51...55).contains(prefix(2)) || (2221...2720).contains(prefix(4)) // Mastercard
                || s.hasPrefix("6011") || s.hasPrefix("65") || (644...649).contains(prefix(3)) // Discover
                || (3528...3589).contains(prefix(4))                  // JCB
                || s.hasPrefix("62")                                  // 银联
        }
    }

    static func luhn(_ digits: [Int]) -> Bool {
        var sum = 0
        for (i, d) in digits.reversed().enumerated() {
            if i % 2 == 1 { let x = d * 2; sum += x > 9 ? x - 9 : x } else { sum += d }
        }
        return sum % 10 == 0
    }

    static func isValidChineseID(_ raw: String) -> Bool {
        let chars = Array(raw.uppercased())
        guard chars.count == 18 else { return false }
        let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
        var sum = 0
        for i in 0..<17 {
            guard let d = chars[i].wholeNumberValue else { return false }
            sum += d * weights[i]
        }
        let check = Array("10X98765432")[sum % 11]
        guard chars[17] == check else { return false }
        // 出生日期必须是真实存在的日子 (正则只挡住了明显不合法的月日)。
        var comps = DateComponents()
        comps.year = Int(String(chars[6..<10])); comps.month = Int(String(chars[10..<12])); comps.day = Int(String(chars[12..<14]))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let date = cal.date(from: comps), cal.component(.day, from: date) == comps.day else { return false }
        return date <= Date()
    }
}
