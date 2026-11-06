import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CopyCore

final class CaptureRulesTests: XCTestCase {
    private func text(_ s: String, from app: String? = "com.apple.Safari", remote: Bool = false) -> RuleSubject {
        RuleSubject(kind: ItemKind.forText(s), text: s, sourceBundleID: app, isRemote: remote)
    }

    private func evaluate(_ rules: CaptureRules, _ subject: RuleSubject, exhaustive: Bool = false) -> CaptureVerdict {
        CaptureEvaluator(rules: rules).evaluate(subject, exhaustive: exhaustive)
    }

    // MARK: 默认规则

    func testEmptyRulesKeepEverything() {
        let v = evaluate(CaptureRules(), text("sk-proj-abcdefghijklmnopqrstuvwxyz0123"))
        XCTAssertEqual(v.outcome, .keep, "CaptureRules() 不启用任何预设")
    }

    func testFactoryDefaultsDropSecretsAndExpireCodes() {
        let rules = CaptureRules.factoryDefault
        XCTAssertEqual(evaluate(rules, text("key: sk-proj-abcdefghijklmnopqrstuvwxyz0123")).outcome, .drop)
        XCTAssertEqual(evaluate(rules, text("【某银行】您的验证码为 482913，5 分钟内有效。")).outcome, .expire(minutes: 5))
        XCTAssertEqual(evaluate(rules, text("4111 1111 1111 1111")).outcome, .keep, "银行卡默认关")
        XCTAssertEqual(evaluate(rules, text("hello world")).outcome, .keep)
    }

    // MARK: 白名单优先

    func testWhitelistKindsGateBeforeBlacklist() {
        var rules = CaptureRules()
        rules.whitelist.enabled = true
        rules.whitelist.kinds = [.text]
        let image = RuleSubject(kind: .image, text: nil, sourceBundleID: "com.apple.Preview")
        let v = evaluate(rules, image)
        XCTAssertEqual(v.outcome, .drop)
        XCTAssertEqual(v.decidedBy, .whitelistKind)
        XCTAssertEqual(evaluate(rules, text("plain")).outcome, .keep)
    }

    func testWhitelistPassThenBlacklistExcludes() {
        var rules = CaptureRules()
        rules.whitelist.enabled = true
        rules.whitelist.apps = ["com.apple.Terminal"]
        rules.blacklist.keywords = [KeywordRule(pattern: "password")]
        // 白名单外的 app: 白名单挡下, 不看黑名单。
        XCTAssertEqual(evaluate(rules, text("ls", from: "com.apple.Safari")).decidedBy, .whitelistApp)
        XCTAssertEqual(evaluate(rules, text("ls", from: nil)).decidedBy, .whitelistApp, "来源未知不算命中白名单 app")
        // 白名单内的 app: 纳入后再过黑名单。
        XCTAssertEqual(evaluate(rules, text("ls", from: "com.apple.Terminal")).outcome, .keep)
        let v = evaluate(rules, text("export PASSWORD=1", from: "com.apple.Terminal"))
        XCTAssertEqual(v.outcome, .drop)
        XCTAssertEqual(v.decidedBy, .blacklistKeyword(rules.blacklist.keywords[0].id))
    }

    func testWhitelistKeywordsSkipImagesAndEmptyListsMeanUnrestricted() {
        var rules = CaptureRules()
        rules.whitelist.enabled = true
        XCTAssertEqual(evaluate(rules, text("anything")).outcome, .keep, "列表为空 = 不限制")
        rules.whitelist.keywords = [KeywordRule(pattern: "TODO")]
        XCTAssertEqual(evaluate(rules, text("todo: buy milk")).outcome, .keep)
        XCTAssertEqual(evaluate(rules, text("buy milk")).decidedBy, .whitelistKeyword)
        let image = RuleSubject(kind: .image, text: nil, sourceBundleID: nil)
        XCTAssertEqual(evaluate(rules, image).outcome, .keep, "图片不做关键词判断")
    }

    func testDisabledListsKeepRulesButIgnoreThem() {
        var rules = CaptureRules()
        rules.whitelist.kinds = []
        rules.blacklist.enabled = false
        rules.blacklist.keywords = [KeywordRule(pattern: "x")]
        XCTAssertEqual(evaluate(rules, text("x")).outcome, .keep)
    }
}

extension CaptureRulesTests {
    // MARK: 关键词

    func testPlainKeywordIgnoresCaseAndWidth() {
        var rules = CaptureRules()
        rules.blacklist.keywords = [KeywordRule(pattern: "Secret")]
        XCTAssertEqual(evaluate(rules, text("my ＳＥＣＲＥＴ note")).outcome, .drop, "全角 + 大写")
        XCTAssertEqual(evaluate(rules, text("secretary")).outcome, .drop, "子串匹配")
        XCTAssertEqual(evaluate(rules, text("public")).outcome, .keep)
    }

    func testRegexMatchesRawTextAndRespectsInlineFlags() {
        var rules = CaptureRules()
        rules.blacklist.keywords = [KeywordRule(pattern: #"^ssh-rsa "#, isRegex: true)]
        XCTAssertEqual(evaluate(rules, text("ssh-rsa AAAAB3Nza")).outcome, .drop)
        XCTAssertEqual(evaluate(rules, text("SSH-RSA AAAAB3Nza")).outcome, .keep, "正则默认区分大小写")
        rules.blacklist.keywords = [KeywordRule(pattern: #"(?i)^ssh-rsa "#, isRegex: true)]
        XCTAssertEqual(evaluate(rules, text("SSH-RSA AAAAB3Nza")).outcome, .drop)
    }

    func testInvalidAndEmptyPatternsAreSkipped() {
        XCTAssertNotNil(CaptureEvaluator.regexError("(unclosed"))
        XCTAssertNil(CaptureEvaluator.regexError(#"\d+"#))
        XCTAssertNil(CaptureEvaluator.regexError(""))
        var rules = CaptureRules()
        rules.blacklist.keywords = [KeywordRule(pattern: "(unclosed", isRegex: true), KeywordRule(pattern: "   ")]
        XCTAssertEqual(evaluate(rules, text("anything (unclosed")).outcome, .keep)
    }

    func testStrictestActionWins() {
        var rules = CaptureRules()
        let a = KeywordRule(pattern: "alpha", action: .expire(minutes: 30))
        let b = KeywordRule(pattern: "beta", action: .expire(minutes: 5))
        let c = KeywordRule(pattern: "gamma", action: .drop)
        rules.blacklist.keywords = [a, b, c]
        let v1 = evaluate(rules, text("alpha beta"))
        XCTAssertEqual(v1.outcome, .expire(minutes: 5))
        XCTAssertEqual(v1.decidedBy, .blacklistKeyword(b.id))
        let v2 = evaluate(rules, text("alpha beta gamma"))
        XCTAssertEqual(v2.outcome, .drop)
        XCTAssertEqual(v2.decidedBy, .blacklistKeyword(c.id))
    }

    func testExhaustiveModeListsEveryHit() {
        var rules = CaptureRules()
        rules.blacklist.apps = ["com.apple.Safari"]
        rules.blacklist.keywords = [KeywordRule(pattern: "x")]
        XCTAssertEqual(evaluate(rules, text("x")).hits.count, 1, "捕获时定了不保存就停")
        XCTAssertEqual(evaluate(rules, text("x"), exhaustive: true).hits.count, 2)
    }

    func testCatastrophicRegexTimesOutInsteadOfHanging() {
        var rules = CaptureRules()
        let bad = KeywordRule(pattern: "(a+)+$", isRegex: true)
        rules.blacklist.keywords = [bad]
        let start = Date()
        let v = evaluate(rules, text(String(repeating: "a", count: 40) + "b"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        XCTAssertEqual(v.outcome, .keep)
        XCTAssertEqual(v.timedOutKeywords, [bad.id])
    }

    // MARK: 预设

    private func only(_ preset: SensitivePreset, action: RuleAction = .drop) -> CaptureRules {
        var rules = CaptureRules()
        rules.blacklist.presets = [PresetSetting(preset: preset, enabled: true, action: action)]
        return rules
    }

    func testSecretsPreset() {
        let rules = only(.secrets)
        for s in ["sk-ant-api03-abcdefghijklmnopqrstuvwxyz",
                  "token=ghp_" + String(repeating: "a1B2", count: 9),
                  "FAKE_AWS_ACCESS_KEY",
                  "-----BEGIN " + "OPENSSH PRIVATE KEY-----\nb3Blbn",
                  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N"] {
            XCTAssertEqual(evaluate(rules, text(s)).outcome, .drop, s)
        }
        for s in ["sk-short", "ask-me-anything-about-this-topic-please", "AKIA123"] {
            XCTAssertEqual(evaluate(rules, text(s)).outcome, .keep, s)
        }
    }

    func testBankCardPresetNeedsLuhnAndIssuerPrefix() {
        let rules = only(.bankCard)
        for s in ["4111111111111111", "卡号 4111 1111 1111 1111 请核对", "5555-5555-5555-4444", "6212345678901265"] {
            XCTAssertEqual(evaluate(rules, text(s)).outcome, .drop, s)
        }
        for s in ["4111111111111112", "1234567890123452", "订单 20261106123456789012", "1730851200000"] {
            XCTAssertEqual(evaluate(rules, text(s)).outcome, .keep, s)
        }
    }

    func testChineseIDPresetChecksChecksumAndDate() {
        let rules = only(.chineseID)
        XCTAssertEqual(evaluate(rules, text("身份证 11010519491231002X")).outcome, .drop)
        XCTAssertEqual(evaluate(rules, text("11010519491231002x")).outcome, .drop, "小写 x")
        XCTAssertEqual(evaluate(rules, text("110105194912310021")).outcome, .keep, "校验位错")
        XCTAssertEqual(evaluate(rules, text("110105194902300020")).outcome, .keep, "2 月 30 日 (校验位是对的)")
    }

    func testVerificationCodePreset() {
        let rules = only(.verificationCode, action: .expire(minutes: 1))
        XCTAssertEqual(evaluate(rules, text("Your verification code is 123456")).outcome, .expire(minutes: 1))
        XCTAssertEqual(evaluate(rules, text("482913", from: SensitiveDetector.messagesBundleID)).outcome, .expire(minutes: 1))
        XCTAssertEqual(evaluate(rules, text("482913", from: "com.apple.Safari")).outcome, .keep, "其他 app 的纯数字不算")
        XCTAssertEqual(evaluate(rules, text("验证码功能的设计文档 " + String(repeating: "正文", count: 200) + " 2026")).outcome,
                       .keep, "长文不算")
        XCTAssertEqual(evaluate(rules, text("请输入验证码")).outcome, .keep, "没有数字")
    }
}

extension CaptureRulesTests {
    // MARK: 长度、大小、通用剪贴板

    static func png(width: Int, height: Int) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    func testLimits() {
        var rules = CaptureRules()
        rules.blacklist.limits.minTextLengthEnabled = true
        rules.blacklist.limits.minTextLength = 3
        rules.blacklist.limits.maxTextKBEnabled = true
        rules.blacklist.limits.maxTextKB = 1
        rules.blacklist.limits.minImagePixelsEnabled = true
        rules.blacklist.limits.minImagePixels = 32
        XCTAssertEqual(evaluate(rules, text("  a \n")).decidedBy, .minTextLength)
        XCTAssertEqual(evaluate(rules, text("a" + String(repeating: " ", count: 5000) + "b")).decidedBy, .maxTextSize)
        XCTAssertEqual(evaluate(rules, text("abc")).outcome, .keep)
        let icon = CapturedItem(kind: .image, plainText: "Image", hashData: Data([1]),
                                representations: [CapturedRepresentation(uti: "public.png", data: Self.png(width: 16, height: 16))],
                                sourceBundleID: nil, sourceAppName: nil)
        XCTAssertEqual(evaluate(rules, RuleSubject(captured: icon, isRemote: false)).decidedBy, .minImagePixels)
        let photo = CapturedItem(kind: .image, plainText: "Image", hashData: Data([2]),
                                 representations: [CapturedRepresentation(uti: "public.png", data: Self.png(width: 20, height: 64))],
                                 sourceBundleID: nil, sourceAppName: nil)
        XCTAssertEqual(evaluate(rules, RuleSubject(captured: photo, isRemote: false)).outcome, .keep, "按长边算")
    }

    func testPreflightDecidesAppsAndUniversalClipboardWithoutContent() {
        var rules = CaptureRules()
        rules.blacklist.apps = ["com.excluded.app"]
        rules.blacklist.skipUniversalClipboard = true
        let ev = CaptureEvaluator(rules: rules)
        XCTAssertEqual(ev.preflight(sourceBundleID: "com.excluded.app", isRemote: false),
                       .decided(CaptureEvaluator.dropped(.blacklistApp("com.excluded.app"))))
        XCTAssertEqual(ev.preflight(sourceBundleID: "com.apple.Safari", isRemote: true),
                       .decided(CaptureEvaluator.dropped(.universalClipboard)))
        XCTAssertEqual(ev.preflight(sourceBundleID: "com.apple.Safari", isRemote: false), .proceed)
        XCTAssertFalse(RulesEngine(rules: rules).shouldCapture(types: ["public.utf8-plain-text", RulesEngine.remoteClipboardType],
                                                               sourceBundleID: "com.apple.Safari"))
    }

    // MARK: 存储格式

    func testCodableRoundTripAndLenientDecoding() throws {
        var rules = CaptureRules.factoryDefault
        rules.whitelist.enabled = true
        rules.blacklist.keywords = [KeywordRule(pattern: "x", isRegex: true, action: .expire(minutes: 10))]
        let data = try JSONEncoder().encode(rules)
        XCTAssertEqual(try JSONDecoder().decode(CaptureRules.self, from: data), rules)

        // 旧数据缺字段、预设只存了一部分: 缺的取默认值, 已有的保留。
        let partial = #"{"blacklist":{"apps":["com.a"],"presets":[{"preset":"bankCard","enabled":true,"action":{"drop":{}}}]}}"#
        let decoded = try JSONDecoder().decode(CaptureRules.self, from: Data(partial.utf8))
        XCTAssertEqual(decoded.blacklist.apps, ["com.a"])
        XCTAssertTrue(decoded.blacklist.enabled)
        XCTAssertFalse(decoded.whitelist.enabled)
        XCTAssertEqual(decoded.whitelist.kinds, Set(ItemKind.selectable))
        XCTAssertEqual(decoded.blacklist.presets.map(\.preset), SensitivePreset.allCases)
        XCTAssertTrue(decoded.blacklist.preset(.bankCard).enabled)
        XCTAssertFalse(decoded.blacklist.preset(.secrets).enabled)
    }
}
