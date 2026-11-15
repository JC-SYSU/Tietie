import AppKit
import TietieCore
import SwiftUI
import UniformTypeIdentifiers

/// 「隐私」页: 共享屏幕时隐藏, 加上捕获规则 (白名单 / 黑名单 / 敏感与限制 / 测试与清理)。
/// 规则存在 `SettingsStore.captureRules`, 改动即时推给剪贴板监控 (`onRulesChange`)。
struct PrivacySettings: View {
    @Bindable var settings: SettingsStore
    let store: ItemStore
    @State private var page: RulesPage = .blacklist

    enum RulesPage: String, CaseIterable, Identifiable {
        case whitelist, blacklist, sensitive, test
        var id: String { rawValue }
        var title: String {
            switch self {
            case .whitelist: return String(localized: "Whitelist")
            case .blacklist: return String(localized: "Blacklist")
            case .sensitive: return String(localized: "Sensitive & Limits")
            case .test: return String(localized: "Test & Clean Up")
            }
        }
    }

    var body: some View {
        SettingsPane {
            // inline tab bar：蓝色底线指示当前页，不会被误读成单选题。
            RulesTabBar(selection: $page)
                .padding(.leading, SettingsLayout.labelWidth + SettingsLayout.columnSpacing)

            switch page {
            case .whitelist: WhitelistRulesPage(settings: settings)
            case .blacklist: BlacklistRulesPage(settings: settings)
            case .sensitive: SensitiveRulesPage(settings: settings)
            case .test: TestRulesPage(settings: settings, store: store)
            }
        }
    }
}

// MARK: - 共用组件

private enum RuleLayout {
    /// 列表控件的宽度 (右栏可用宽度约 400pt)。
    static let listWidth: CGFloat = 534
}

extension ItemKind {
    /// 规则页里的类型名。
    var ruleTitle: String {
        switch self {
        case .text: return String(localized: "Text")
        case .richText: return String(localized: "Rich Text")
        case .link: return String(localized: "Link")
        case .image: return String(localized: "Image")
        case .file: return String(localized: "Files")
        case .color: return String(localized: "Color")
        }
    }
}

/// 一排类型复选框, 绑定到一个类型集合。
private struct KindChecklist: View {
    @Binding var kinds: Set<ItemKind>

    var body: some View {
        HStack(spacing: 14) {
            ForEach(ItemKind.selectable, id: \.self) { kind in
                Toggle(kind.ruleTitle, isOn: Binding(
                    get: { kinds.contains(kind) },
                    set: { on in if on { kinds.insert(kind) } else { kinds.remove(kind) } }))
                
            }
        }
    }
}

/// 规则生效次数。0 次不显示数字, 只占位保持对齐。
private struct HitCount: View {
    let count: Int

    var body: some View {
        Text(count > 0 ? "\(count)" : "")
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 34, alignment: .trailing)
            .help(String(localized: "Times this rule took effect"))
    }
}

/// 命中后的处理: 不保存 / N 分钟后删除。
private struct ActionPicker: View {
    @Binding var action: RuleAction

    var body: some View {
        let options: [(RuleAction, String)] = [(RuleAction.drop, String(localized: "Don't Save"))]
            + RuleAction.expireChoices.map { m in
                (RuleAction.expire(minutes: m), String(format: String(localized: "Delete after %d min"), m))
            }
        KleinPopUp(options: options, selection: $action)
            .frame(width: 176)
    }
}

/// 整数输入框 + 步进器, 值限制在 range 里。
private struct NumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                      format: .number.grouping(.never))
                .textFieldStyle(KleinTextFieldStyle())
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
            KleinStepper(value: $value, range: range)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

/// App 列表 (bundle ID), 下面是经典的 + / − 按钮条。
private struct AppListEditor: View {
    @Binding var bundleIDs: [String]
    var hitCount: (String) -> Int = { _ in 0 }
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if bundleIDs.isEmpty {
                    Text("No apps")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    List(bundleIDs, id: \.self, selection: $selection) { id in
                        HStack(spacing: 8) {
                            if let icon = AppIconCache.icon(forBundleID: id) {
                                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "app.dashed").frame(width: 18, height: 18).foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(appDisplayName(id))
                                Text(id).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            HitCount(count: hitCount(id))
                        }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                }
            }
            .frame(width: RuleLayout.listWidth, height: 140)
            .background(Color.white.opacity(0.76))
            .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))

            ListButtonBar(add: addApp, remove: removeSelected, canRemove: selection != nil)
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        bundleIDs = Array(Set(bundleIDs + ids)).sorted()
    }

    private func removeSelected() {
        guard let selection else { return }
        bundleIDs.removeAll { $0 == selection }
        self.selection = nil
    }
}

/// 列表下沿的 + / − 按钮条。
private struct ListButtonBar: View {
    let add: () -> Void
    var remove: (() -> Void)? = nil
    var canRemove = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: add) { Image(systemName: "plus") }
                .buttonStyle(KleinIconButtonStyle())
                .accessibilityLabel(String(localized: "Add"))
            if let remove {
                Divider().frame(height: 14)
                Button(action: remove) { Image(systemName: "minus") }
                    .buttonStyle(KleinIconButtonStyle())
                    .accessibilityLabel(String(localized: "Remove"))
                    .disabled(!canRemove)
            }
            Spacer()
        }
        .frame(width: RuleLayout.listWidth)
        .background(Color.white.opacity(0.60))
        .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .offset(y: -1)
    }
}

func appDisplayName(_ bundleID: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
}

/// 关键词列表: 每行 = 内容 + 「正则」开关 (+ 黑名单的处理方式) + 生效次数 + 删除按钮。
private struct KeywordListEditor: View {
    @Binding var rules: [KeywordRule]
    /// 黑名单显示处理方式; 白名单的关键词只决定纳入, 不显示。
    let showsAction: Bool
    var hitCount: (KeywordRule) -> Int = { _ in 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if rules.isEmpty {
                        Text("No keywords").foregroundStyle(.secondary).padding(.top, 2)
                    }
                    // 遍历快照而不是 $rules: 删除一行时不会访问到已经不存在的下标。
                    ForEach(rules) { rule in
                        KeywordRow(rule: binding(for: rule.id), showsAction: showsAction,
                                   count: hitCount(rule), remove: { rules.removeAll { $0.id == rule.id } })
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: RuleLayout.listWidth, height: 112)
            .background(Color.white.opacity(0.76))
            .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))

            ListButtonBar(add: { rules.append(KeywordRule()) })
        }
    }

    private func binding(for id: UUID) -> Binding<KeywordRule> {
        Binding(
            get: { rules.first { $0.id == id } ?? KeywordRule(id: id) },
            set: { new in if let i = rules.firstIndex(where: { $0.id == id }) { rules[i] = new } })
    }
}

private struct KeywordRow: View {
    @Binding var rule: KeywordRule
    let showsAction: Bool
    let count: Int
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                TextField(rule.isRegex ? String(localized: "Regular expression") : String(localized: "Keyword"),
                          text: $rule.pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(rule.isRegex ? .system(size: 12, design: .monospaced) : .system(size: 12))
                    .frame(minWidth: 110)
                Toggle(String(localized: "Regex"), isOn: $rule.isRegex)
                    
                    .fixedSize()
                if showsAction {
                    ActionPicker(action: $rule.action).controlSize(.small)
                }
                HitCount(count: count)
                Button(action: remove) { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "Remove"))
            }
            if rule.isRegex, let error = CaptureEvaluator.regexError(rule.pattern) {
                Text(String(format: String(localized: "Invalid regex, ignored: %@"), error))
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - 白名单

private struct WhitelistRulesPage: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        let on = settings.captureRules.whitelist.enabled
        SettingsRow(label: String(localized: "Whitelist:"),
                    help: withHits(String(localized: "Only content that meets every condition below is kept. Empty lists don't restrict anything."),
                                   settings.hitCount(.whitelistKind) + settings.hitCount(.whitelistApp) + settings.hitCount(.whitelistKeyword),
                                   String(localized: "%d items skipped so far."))) {
            Toggle(String(localized: "Only keep matching content"), isOn: $settings.captureRules.whitelist.enabled)
                
        }
        Group {
            SettingsRow(label: String(localized: "Types:"),
                        help: String(localized: "Rich text is formatted text, e.g. copied from a web page or a document.")) {
                KindChecklist(kinds: $settings.captureRules.whitelist.kinds)
            }
            SettingsRow(label: String(localized: "Source Apps:"),
                        help: String(localized: "When the list isn't empty, content from other apps, or with an unknown source, is skipped.")) {
                AppListEditor(bundleIDs: $settings.captureRules.whitelist.apps)
            }
            SettingsRow(label: String(localized: "Keywords:"),
                        help: String(localized: "Keep text that contains any of these. Images aren't checked against keywords.")) {
                KeywordListEditor(rules: $settings.captureRules.whitelist.keywords, showsAction: false)
            }
        }
        .disabled(!on)
        .opacity(on ? 1 : 0.55)
    }
}

// MARK: - 黑名单

private struct BlacklistRulesPage: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        let on = settings.captureRules.blacklist.enabled
        SettingsRow(label: String(localized: "Blacklist:"),
                    help: String(localized: "Content matching any rule is handled by that rule. Also turns sensitive content and size limits on or off.")) {
            Toggle(String(localized: "Exclude matching content"), isOn: $settings.captureRules.blacklist.enabled)
                
        }
        Group {
            SettingsRow(label: String(localized: "Types:"),
                        help: withHits(String(localized: "Checked types are never saved."),
                                       ItemKind.selectable.reduce(0) { $0 + settings.hitCount(.blacklistKind($1)) },
                                       String(localized: "Skipped %d times."))) {
                KindChecklist(kinds: $settings.captureRules.blacklist.kinds)
            }
            SettingsRow(label: String(localized: "Source Apps:"),
                        help: String(localized: "Tietie records nothing while one of these apps is in front. Concealed content from password managers is never recorded.")) {
                AppListEditor(bundleIDs: $settings.captureRules.blacklist.apps,
                              hitCount: { settings.hitCount(.blacklistApp($0)) })
            }
            SettingsRow(label: String(localized: "Keywords:"),
                        help: String(localized: "Plain keywords ignore case and full-width forms. Regular expressions match the original text; add (?i) to ignore case.")) {
                KeywordListEditor(rules: $settings.captureRules.blacklist.keywords, showsAction: true,
                                  hitCount: { settings.hitCount(.blacklistKeyword($0.id)) })
            }
        }
        .disabled(!on)
        .opacity(on ? 1 : 0.55)
    }
}

/// 说明文字后面接「已生效 N 次」, 0 次不接。
private func withHits(_ help: String, _ count: Int, _ format: String) -> String {
    count > 0 ? help + " " + String(format: format, count) : help
}

// MARK: - 敏感内容与限制

extension SensitivePreset {
    var title: String {
        switch self {
        case .secrets: return String(localized: "Keys & Tokens")
        case .bankCard: return String(localized: "Bank Card Numbers")
        case .chineseID: return String(localized: "Chinese ID Numbers")
        case .verificationCode: return String(localized: "Verification Codes")
        }
    }

    var detail: String {
        switch self {
        case .secrets: return String(localized: "API keys (sk-, ghp_, AKIA…), private keys, JWTs")
        case .bankCard: return String(localized: "13–19 digits with a card issuer prefix and a valid Luhn check digit")
        case .chineseID: return String(localized: "18 digits with a real birth date and a valid check digit")
        case .verificationCode: return String(localized: "4–8 digits from Messages, or short text with \"验证码\" / \"code\" and digits")
        }
    }
}

private struct SensitiveRulesPage: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        let on = settings.captureRules.blacklist.enabled
        if !on {
            SettingsRow(label: "") {
                Text("These rules are part of the blacklist, which is off.").foregroundStyle(.orange)
            }
        }
        Group {
            SettingsRow(label: String(localized: "Sensitive Content:"),
                        help: String(localized: "Each rule also verifies check digits to avoid false matches. Only the first 64K characters of a copy are checked.")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(SensitivePreset.allCases, id: \.self) { preset in
                        let setting = presetBinding(preset)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Toggle(preset.title, isOn: setting.enabled)
                                Spacer(minLength: 8)
                                ActionPicker(action: setting.action).controlSize(.small).disabled(!setting.wrappedValue.enabled)
                                HitCount(count: settings.hitCount(.preset(preset)))
                            }
                            Text(preset.detail).font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 20)
                        }
                    }
                }
                .frame(width: RuleLayout.listWidth)
            }

            SettingsDivider()

            SettingsRow(label: String(localized: "Universal Clipboard:"),
                        help: withHits(String(localized: "Content handed over from your iPhone, iPad or another Mac."),
                                       settings.hitCount(.universalClipboard), String(localized: "Skipped %d times."))) {
                Toggle(String(localized: "Don't save content from other devices"),
                       isOn: $settings.captureRules.blacklist.skipUniversalClipboard)
                    
            }

            SettingsRow(label: String(localized: "Text:")) {
                VStack(alignment: .leading, spacing: 6) {
                    limitRow(String(localized: "Skip text shorter than"), $settings.captureRules.blacklist.limits.minTextLengthEnabled,
                             $settings.captureRules.blacklist.limits.minTextLength, 1...100, String(localized: "characters"), .minTextLength)
                    limitRow(String(localized: "Skip text larger than"), $settings.captureRules.blacklist.limits.maxTextKBEnabled,
                             $settings.captureRules.blacklist.limits.maxTextKB, 1...100_000, "KB", .maxTextSize)
                }
            }
            SettingsRow(label: String(localized: "Images:")) {
                VStack(alignment: .leading, spacing: 6) {
                    limitRow(String(localized: "Skip images smaller than"), $settings.captureRules.blacklist.limits.minImagePixelsEnabled,
                             $settings.captureRules.blacklist.limits.minImagePixels, 1...4096, String(localized: "px (longer side)"), .minImagePixels)
                    limitRow(String(localized: "Skip images larger than"), $settings.captureRules.blacklist.limits.maxImageMBEnabled,
                             $settings.captureRules.blacklist.limits.maxImageMB, 1...100, "MB", .maxImageSize)
                }
            }
        }
        .disabled(!on)
        .opacity(on ? 1 : 0.55)
    }

    private func limitRow(_ title: String, _ enabled: Binding<Bool>, _ value: Binding<Int>,
                          _ range: ClosedRange<Int>, _ unit: String, _ rule: RuleRef) -> some View {
        HStack(spacing: 6) {
            Toggle(title, isOn: enabled)
            NumberField(value: value, range: range, unit: unit).disabled(!enabled.wrappedValue)
            Spacer(minLength: 0)
            HitCount(count: settings.hitCount(rule))
        }
        .frame(width: RuleLayout.listWidth)
    }

    private func presetBinding(_ preset: SensitivePreset) -> Binding<PresetSetting> {
        Binding(
            get: { settings.captureRules.blacklist.preset(preset) },
            set: { new in
                if let i = settings.captureRules.blacklist.presets.firstIndex(where: { $0.preset == preset }) {
                    settings.captureRules.blacklist.presets[i] = new
                } else {
                    settings.captureRules.blacklist.presets.append(new)
                }
            })
    }
}

// MARK: - 测试与清理

private struct TestRulesPage: View {
    @Bindable var settings: SettingsStore
    let store: ItemStore
    @State private var sample = ""
    @State private var sourceApp = ""
    @State private var apps: [String] = []
    @State private var plan: RuleCleanupPlan?
    @State private var planning = false
    @State private var confirmCleanup = false
    @State private var cleanupResult: String?

    var body: some View {
        SettingsRow(label: String(localized: "Test:"),
                    help: String(localized: "Paste a sample to see what the current rules would do with it. Nothing is saved.")) {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $sample)
                    .font(.system(size: 12))
                    .frame(width: RuleLayout.listWidth, height: 64)
                    .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                HStack(spacing: 8) {
                    Text(String(localized: "Copied from")).font(.system(size: 12)).foregroundStyle(.secondary)
                    KleinPopUp(options: [("", String(localized: "Unknown app"))]
                        + apps.map { ($0, appDisplayName($0)) },
                               selection: $sourceApp)
                        .frame(width: 200)
                }
                if !sample.isEmpty { TestResultView(verdict: verdict, rules: settings.captureRules) }
            }
        }

        SettingsDivider()

        SettingsRow(label: String(localized: "Statistics:"), help: statsHelp) {
            Button(String(localized: "Reset Counts")) { settings.resetRuleHits() }
                .buttonStyle(KleinButtonStyle())
                .disabled(settings.ruleHitCounts.isEmpty)
        }

        SettingsRow(label: String(localized: "History:"),
                    help: String(localized: "Checks existing history against the current rules. You'll see how many items are affected before anything is deleted. Favorites and pinboard items are skipped; the Universal Clipboard rule can't be checked for old items.")) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Button(String(localized: "Apply Rules to History…")) { makePlan() }
                        .buttonStyle(KleinButtonStyle())
                        .disabled(planning)
                    if planning { ProgressView().controlSize(.small) }
                }
                if let cleanupResult { SettingsHelp(cleanupResult) }
            }
        }
        .onAppear { loadApps() }
        .confirmationDialog(String(localized: "Apply rules to history?"), isPresented: $confirmCleanup, presenting: plan) { plan in
            Button(String(localized: "Apply"), role: .destructive) { apply(plan) }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { plan in
            Text(planSummary(plan))
        }
    }

    private var verdict: CaptureVerdict {
        // 与捕获时一致: 去掉末尾换行后判断类型和内容。
        let text = TrailingNewlines.trimmed(sample)
        let kind: ItemKind = HexColor.isColorText(text) ? .color : ItemKind.forText(text)
        return CaptureEvaluator(rules: settings.captureRules)
            .evaluate(RuleSubject(kind: kind, text: text, sourceBundleID: sourceApp.isEmpty ? nil : sourceApp),
                      exhaustive: true, budget: 0.2)
    }

    private var statsHelp: String {
        let total = settings.ruleHitCounts.values.reduce(0, +)
        return total == 0 ? String(localized: "No rule has taken effect yet.")
            : String(format: String(localized: "Rules have taken effect %d times. Counts are stored, the content isn't."), total)
    }

    private func loadApps() {
        let used = ((try? store.distinctApps()) ?? []).map(\.bundleID)
        let listed = settings.captureRules.whitelist.apps + settings.captureRules.blacklist.apps
        apps = Array(Set(used + listed + ["com.apple.MobileSMS"])).sorted { appDisplayName($0) < appDisplayName($1) }
    }

    private func makePlan() {
        planning = true
        cleanupResult = nil
        let rules = settings.captureRules
        let store = self.store
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try store.planRuleCleanup(rules) }
            DispatchQueue.main.async {
                planning = false
                switch result {
                case .success(let p) where p.isEmpty:
                    cleanupResult = String(format: String(localized: "Checked %d items; none match the current rules."), p.scanned)
                case .success(let p):
                    plan = p
                    confirmCleanup = true
                case .failure(let error):
                    cleanupResult = error.localizedDescription
                }
            }
        }
    }

    private func apply(_ plan: RuleCleanupPlan) {
        let store = self.store
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try store.apply(plan) }
            DispatchQueue.main.async {
                switch result {
                case .success(let r):
                    cleanupResult = String(format: String(localized: "Deleted %d items; %d more will be deleted when their time is up."),
                                           r.deleted, r.expiring)
                    settings.onExpiryScheduleChange?()
                case .failure(let error):
                    cleanupResult = error.localizedDescription
                }
            }
        }
    }

    private func planSummary(_ plan: RuleCleanupPlan) -> String {
        var lines = [String(format: String(localized: "%d items will be deleted now; %d will be deleted when their time is up."),
                            plan.deleteIDs.count, plan.expireAt.count)]
        for (rule, n) in plan.countsByRule.sorted(by: { $0.value > $1.value }).prefix(6) {
            lines.append("· \(ruleTitle(rule, settings.captureRules)): \(n)")
        }
        lines.append(String(localized: "Favorites and pinboard items are kept. This cannot be undone."))
        return lines.joined(separator: "\n")
    }
}

private struct TestResultView: View {
    let verdict: CaptureVerdict
    let rules: CaptureRules

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch verdict.outcome {
            case .keep:
                Label(String(localized: "Would be saved"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .expire(let m):
                Label(String(format: String(localized: "Would be saved and deleted after %d min"), m), systemImage: "timer")
                    .foregroundStyle(.orange)
            case .drop:
                Label(String(localized: "Would not be saved"), systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
            if let rule = verdict.decidedBy {
                SettingsHelp(String(format: String(localized: "Decided by: %@"), ruleTitle(rule, rules)))
            }
            let others = verdict.hits.map(\.rule).filter { $0 != verdict.decidedBy }
            if !others.isEmpty {
                SettingsHelp(String(format: String(localized: "Also matched: %@"),
                                    others.map { ruleTitle($0, rules) }.joined(separator: "; ")))
            }
            if !verdict.timedOutKeywords.isEmpty || !verdict.timedOutPresets.isEmpty {
                let names = verdict.timedOutKeywords.compactMap { id in keywordPattern(id, rules) }
                    + verdict.timedOutPresets.map(\.title)
                Text(String(format: String(localized: "Took too long and was treated as no match: %@"), names.joined(separator: "; ")))
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        .font(.system(size: 12, weight: .medium))
    }
}

private func keywordPattern(_ id: UUID, _ rules: CaptureRules) -> String? {
    (rules.blacklist.keywords + rules.whitelist.keywords).first { $0.id == id }.map { "“\($0.pattern)”" }
}

/// 规则在界面上的名字。
private func ruleTitle(_ rule: RuleRef, _ rules: CaptureRules) -> String {
    switch rule {
    case .whitelistKind: return String(localized: "Whitelist: type not included")
    case .whitelistApp: return String(localized: "Whitelist: app not in the list")
    case .whitelistKeyword: return String(localized: "Whitelist: no keyword matched")
    case .blacklistKind(let k): return String(format: String(localized: "Blacklist type: %@"), k.ruleTitle)
    case .blacklistApp(let id): return String(format: String(localized: "Blacklist app: %@"), appDisplayName(id))
    case .universalClipboard: return String(localized: "Universal Clipboard")
    case .minTextLength: return String(localized: "Text too short")
    case .maxTextSize: return String(localized: "Text too large")
    case .minImagePixels: return String(localized: "Image too small")
    case .maxImageSize: return String(localized: "Image too large")
    case .preset(let p): return p.title
    case .blacklistKeyword(let id):
        return String(format: String(localized: "Blacklist keyword: %@"), keywordPattern(id, rules) ?? "?")
    }
}

// MARK: - Inline tab bar for rules pages

private struct RulesTabBar: View {
    @Binding var selection: PrivacySettings.RulesPage

    var body: some View {
        KleinSegmented(options: PrivacySettings.RulesPage.allCases.map { ($0, $0.title) },
                       selection: $selection)
            .frame(width: 480)
    }
}

private struct RulesTabItem: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? SettingsTheme.klein : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                // 底部指示条
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(isSelected ? SettingsTheme.klein : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .background(hovered && !isSelected ? Color.primary.opacity(0.04) : Color.clear)
        .onHover { hovered = $0 }
    }
}
