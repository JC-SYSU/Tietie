import AppKit

/// 去掉文本末尾的换行 (用户决定: 无开关, 始终生效)。目的: 粘贴命令到终端时不因末尾
/// 换行直接执行, 粘贴到文档时不多出空行。
///
/// 规则: 只删末尾那一段**连续的**换行字符, 末尾的空格/tab 保留 ("ls \n" → "ls "),
/// 换行与空格交替时只删最后那段 ("a\n \n" → "a\n ")。换行的判定交给
/// `Character.isNewline`, 覆盖 LF、CR、CRLF (Swift 里是一个 Character)、VT、FF、
/// NEL (U+0085)、LS (U+2028)、PS (U+2029)。
///
/// 三处调用: 入库 (`ClipboardMonitor.snapshot`)、从 Copy 粘贴 (`PasteService.place`,
/// 兜住改动前就已入库的旧条目)、可选的系统剪贴板改写 (`ClipboardMonitor`)。
public enum TrailingNewlines {
    static let utf8PlainText = "public.utf8-plain-text"

    /// 系统会从 UTF-8 文本或 RTF 自动派生这些类型 (实测 NSPasteboard 写入 utf8 + rtf 后
    /// item 上自动出现 utf16-external)。改写剪贴板时只写 UTF-8 一份, 其余丢弃, 避免残留
    /// 带换行的旧副本。
    static let plainTextUTIs: Set<String> = [
        utf8PlainText,
        "public.utf16-plain-text",
        "public.utf16-external-plain-text",
        "public.plain-text",
    ]

    static let richTextTypes: [String: NSAttributedString.DocumentType] = [
        "public.rtf": .rtf,
        "com.apple.flat-rtfd": .rtfd,
    ]

    /// 超过这个大小的 RTF 不做往返解析, 原样保留 (只去纯文本的换行)。捕获在主线程
    /// 轮询里跑, 带内嵌图片的大文档解析会卡住界面。
    static let maxRichTextBytes = 4_000_000

    public static func endsWithNewline(_ text: String) -> Bool {
        text.last?.isNewline == true
    }

    /// 去掉末尾连续换行后的文本, 可能为空串 (原文全是换行时)。
    public static func trimmed(_ text: String) -> String {
        guard endsWithNewline(text) else { return text }
        guard let lastKept = text.lastIndex(where: { !$0.isNewline }) else { return "" }
        return String(text[...lastKept])
    }

    /// RTF/RTFD 数据去掉末尾换行 (段落标记) 后重新编码, 字体颜色等属性随
    /// NSAttributedString 往返保留。无需改动、解析失败、超过大小上限、去完为空时
    /// 返回 nil, 调用方保留原数据。
    static func strippedRichText(_ data: Data, type: NSAttributedString.DocumentType) -> Data? {
        guard data.count <= maxRichTextBytes,
              let attributed = try? NSMutableAttributedString(
                data: data, options: [.documentType: type], documentAttributes: nil)
        else { return nil }
        let full = attributed.string
        let kept = trimmed(full)
        let keptLength = kept.utf16.count
        let fullLength = full.utf16.count
        // trimmed 按整个 Character 删, 所以 keptLength 一定落在 UTF-16 字符边界上。
        guard !kept.isEmpty, keptLength < fullLength else { return nil }
        attributed.deleteCharacters(in: NSRange(location: keptLength, length: fullLength - keptLength))
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: type])
    }

    /// 一组表示 (同一条内容的不同格式) 去掉末尾换行: UTF-8 纯文本必删; RTF/RTFD 尽量删,
    /// 删不了就原样保留; HTML 和其他类型不动。以 UTF-8 纯文本为准判断要不要处理——它不以
    /// 换行结尾就整组不动 (也就不用解析 RTF)。无需改动时返回 nil。
    public static func strip(_ representations: [CapturedRepresentation]) -> [CapturedRepresentation]? {
        guard let plain = representations.first(where: { $0.uti == utf8PlainText }),
              let text = String(data: plain.data, encoding: .utf8),
              endsWithNewline(text) else { return nil }
        let kept = trimmed(text)
        // 全是换行的内容保持原样, 不产生空条目。
        guard !kept.isEmpty else { return nil }
        return representations.map { rep in
            if rep.uti == utf8PlainText {
                return CapturedRepresentation(uti: rep.uti, data: Data(kept.utf8))
            }
            if let type = richTextTypes[rep.uti], let data = strippedRichText(rep.data, type: type) {
                return CapturedRepresentation(uti: rep.uti, data: data)
            }
            return rep
        }
    }

    /// 改写系统剪贴板用: `original` 是剪贴板上那一项的全部类型, `text` 是
    /// `NSPasteboard.string()` 读到的文本。所有纯文本类型合并成一份 UTF-8 (放在第一个纯
    /// 文本类型原来的位置), 再走 `strip`。其他类型 (含 app 私有类型) 原样保留, 尽量让源
    /// app 自己粘贴时还认得。无需改动时返回 nil。
    public static func pasteboardRewrite(_ original: [CapturedRepresentation],
                                         text: String) -> [CapturedRepresentation]? {
        let plain = CapturedRepresentation(uti: utf8PlainText, data: Data(text.utf8))
        var reps: [CapturedRepresentation] = []
        var placedPlain = false
        for rep in original {
            if plainTextUTIs.contains(rep.uti) {
                if !placedPlain { reps.append(plain); placedPlain = true }
            } else {
                reps.append(rep)
            }
        }
        if !placedPlain { reps.append(plain) }
        return strip(reps)
    }
}
