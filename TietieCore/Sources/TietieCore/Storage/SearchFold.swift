import Foundation

/// 命中摘要用的「按码点查表」归一化 (见 SearchSnippet): 把原文 UTF-8 一遍折叠成
/// `SearchText.normalize` 的结果, 同时记下每个改变了字节的码点在原文里的位置, 用来把归一化
/// 文本里的命中映射回原文。表里每个码点的结果都直接取自 `SearchText.normalize`, 所以与搜索
/// 用的规则一致。不能用 Unicode 的 changesWhenNFKCCaseFolded 筛出候选码点再建表: Foundation
/// 的大小写折叠与它有 107 处不同 (切罗基字母、ǰ/ΐ 等), 只有逐个码点实算才可靠。
///
/// 逐码点查表与整段归一化只在相邻码点不会合成时等价, 以下码点标为「退回」, 文本里出现就不走
/// 这条路径: 组合类非 0 的; 归一化结果里含组合类非 0 字符的; 组合类为 0 但会和前后字符合成的
/// (印度系元音、缅文、韩文字母、巴厘文); 以及没逐个核对过的补充平面区。
public final class SearchFoldTable: @unchecked Sendable {
    enum Entry: Equatable { case identity, bail, fold([UInt8]) }

    static let bailCode: UInt32 = .max
    /// 0 = 不变; bailCode = 退回; 其他 = 结果在 pool 里的 (偏移 << 8 | 长度)。
    let bmp: [UInt32]
    /// 逐个核对过的补充平面码点 (含不变的, 值为 0)。
    let supp: [UInt32: UInt32]
    let pool: [UInt8]

    /// 补充平面里逐个核对的区: 数学字母数字、emoji 与符号、兼容汉字补充、标签、变体选择符补充。
    static let checkedSupplementary: [ClosedRange<UInt32>] = [
        0x1D400...0x1D7FF, 0x1F000...0x1FAFF, 0x2F800...0x2FA1F, 0xE0000...0xE007F, 0xE0100...0xE01EF,
    ]
    /// 补充平面里直接视为不变的汉字扩展区 B–I (不含兼容汉字补充), 由测试整段核对。
    static let identityHanSupplementary: [ClosedRange<UInt32>] = [0x20000...0x2A6DF, 0x2A700...0x2EE5F, 0x30000...0x323AF]

    init() {
        var bmp = [UInt32](repeating: 0, count: 0x10000)
        var supp: [UInt32: UInt32] = [:]
        var pool: [UInt8] = []
        func code(_ v: UInt32) -> UInt32 {
            switch Self.classify(v) {
            case .identity: return 0
            case .bail: return Self.bailCode
            case .fold(let bytes): defer { pool += bytes }; return UInt32(pool.count) << 8 | UInt32(bytes.count)
            }
        }
        for v in UInt32(0x80)...0xFFFF where !(0xD800...0xDFFF).contains(v) { bmp[Int(v)] = code(v) }
        for range in Self.checkedSupplementary { for v in range { supp[v] = code(v) } }
        self.bmp = bmp
        self.supp = supp
        self.pool = pool
    }

    static func classify(_ v: UInt32) -> Entry {
        guard let scalar = Unicode.Scalar(v), !isComposingRange(v),
              scalar.properties.canonicalCombiningClass.rawValue == 0 else { return .bail }
        let original = String(Character(scalar))
        let normalized = SearchText.normalize(original)
        // 按字节比: String 的 == 是规范等价, "Å"(U+212B) 和 "Å"(U+00C5) 会被判为相等。
        if normalized.utf8.elementsEqual(original.utf8) { return .identity }
        guard !normalized.isEmpty, normalized.utf8.count <= 255,
              !normalized.unicodeScalars.contains(where: { $0.properties.canonicalCombiningClass.rawValue != 0 || isComposingRange($0.value) })
        else { return .bail }
        return .fold(Array(normalized.utf8))
    }

    /// 组合类为 0 却会和相邻字符合成的区。
    static func isComposingRange(_ v: UInt32) -> Bool {
        switch v {
        case 0x0900...0x0DFF, 0x1000...0x109F, 0x1100...0x11FF, 0x1B00...0x1B7F,
             0x3130...0x318F, 0xA960...0xA97F, 0xD7B0...0xD7FF, 0xFFA0...0xFFDC: return true
        default: return false
        }
    }

    @inline(__always) func code(for v: UInt32) -> UInt32 {
        if v <= 0xFFFF { return bmp[Int(v)] }
        if let c = supp[v] { return c }
        return Self.identityHanSupplementary.contains { $0.contains(v) } ? 0 : Self.bailCode
    }

    func entry(_ v: UInt32) -> Entry {
        if v < 0x80 { return .identity }
        let c = code(for: v)
        if c == 0 { return .identity }
        if c == Self.bailCode { return .bail }
        return .fold(Array(pool[Int(c >> 8)..<Int(c >> 8) + Int(c & 0xFF)]))
    }

    // MARK: - 共享实例

    private static let lock = NSLock()
    private static var shared: SearchFoldTable?

    /// 已建好的共享表; 还没建好时为 nil, 摘要退回旧做法。
    public static var current: SearchFoldTable? {
        lock.lock(); defer { lock.unlock() }
        return shared
    }

    /// 建表 (BMP 每个码点调一次 normalize: release 约 60ms、debug 约 100ms, 占 256KB)。
    /// app 启动时在后台调用; 已建好就直接返回。不在锁里建, 免得主线程读 `current` 时被挡住。
    @discardableResult
    public static func prepare() -> SearchFoldTable {
        if let table = current { return table }
        let built = SearchFoldTable()
        lock.lock(); defer { lock.unlock() }
        if shared == nil { shared = built }
        return shared!
    }
}

/// 一段原文折叠后的结果。
struct SearchFolded {
    /// 改变了字节的一个码点: 折叠后从 `f` 起 `flen` 字节, 对应原文从 `r` 起 `rlen` 字节。
    struct Event { let f: Int, r: Int, flen: Int, rlen: Int }

    /// 归一化后的 UTF-8 (等于 `SearchText.normalize(原文)`, 由测试和对账核对)。
    let bytes: [UInt8]
    /// 按位置升序。没有记录的字节 (含 ASCII 大写转小写) 与原文一一对应。
    let events: [Event]

    func find(_ needle: [UInt8], from: Int = 0) -> Int? {
        guard !needle.isEmpty, from >= 0, from + needle.count <= bytes.count else { return nil }
        return bytes.withUnsafeBytes { hay in
            needle.withUnsafeBytes { n in
                memmem(hay.baseAddress! + from, hay.count - from, n.baseAddress!, n.count)
                    .map { UnsafeRawPointer($0) - hay.baseAddress! }
            }
        }
    }

    /// 折叠后偏移 → 原文字节偏移; 落在展开字符 (如 "ﬃ"→"ffi") 内部时取该字符的起点。
    func rawStart(_ f: Int) -> Int {
        guard let e = lastEvent(where: { $0.f <= f }) else { return f }
        return f < e.f + e.flen ? e.r : e.r + e.rlen + (f - e.f - e.flen)
    }

    /// 一个命中的最后一个字节所在原文字符的结束偏移。命中的查询词是完整 UTF-8, 不在展开字符
    /// 内部时结尾就在字符边界上, 下一个字节即结束。
    func rawEnd(lastByte f: Int) -> Int {
        if let e = lastEvent(where: { $0.f <= f }), f < e.f + e.flen { return e.r + e.rlen }
        return rawStart(f) + 1
    }

    /// 原文字节偏移 (字符边界) → 折叠后偏移。
    func folded(forRaw r: Int) -> Int {
        guard let e = lastEvent(where: { $0.r <= r }) else { return r }
        return r < e.r + e.rlen ? e.f : e.f + e.flen + (r - e.r - e.rlen)
    }

    private func lastEvent(where isBefore: (Event) -> Bool) -> Event? {
        var lo = 0, hi = events.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if isBefore(events[mid]) { lo = mid + 1 } else { hi = mid }
        }
        return lo == 0 ? nil : events[lo - 1]
    }
}

extension SearchFoldTable {
    /// 折叠一段原文; 含需要退回的码点时返回 nil。
    func fold(_ text: Substring) -> SearchFolded? {
        text.utf8.withContiguousStorageIfAvailable(foldBytes) ?? Array(text.utf8).withUnsafeBufferPointer(foldBytes)
    }

    /// 不变的字节成段拷贝, 只有改变字节的码点单独处理; ASCII 大写只记下位置, 最后逐个改成小写。
    /// 发布用的是 debug 构建 (不做优化), 逐字节 append 或逐字节再扫一遍输出都会慢 5–15 倍
    /// (实测 25 张长卡: 再扫一遍输出转小写 19–28ms, 现在的写法整个折叠约 2ms), 所以这样写。
    private func foldBytes(_ raw: UnsafeBufferPointer<UInt8>) -> SearchFolded? {
        guard let base = raw.baseAddress else { return SearchFolded(bytes: [], events: []) }
        let n = raw.count
        var out = [UInt8]()
        out.reserveCapacity(n + n / 8)
        var events: [SearchFolded.Event] = []
        var upper: [Int] = []
        var runStart = 0
        var i = 0
        while i < n {
            let b = base[i]
            if b < 0x80 {
                // 这个字节将落在 out 的这个位置: 前面已拷贝的 + 本段内的偏移。
                if b &- 0x41 < 26 { upper.append(out.count + i - runStart) }
                i += 1
                continue
            }
            let len: Int, v: UInt32
            if b >= 0xF0 { len = 4 } else if b >= 0xE0 { len = 3 } else { len = 2 }
            guard i + len <= n else { return nil }
            switch len {
            case 2: v = UInt32(b & 0x1F) << 6 | UInt32(base[i + 1] & 0x3F)
            case 3: v = UInt32(b & 0x0F) << 12 | UInt32(base[i + 1] & 0x3F) << 6 | UInt32(base[i + 2] & 0x3F)
            default: v = UInt32(b & 0x07) << 18 | UInt32(base[i + 1] & 0x3F) << 12 | UInt32(base[i + 2] & 0x3F) << 6 | UInt32(base[i + 3] & 0x3F)
            }
            let c = code(for: v)
            if c == 0 { i += len; continue }
            if c == Self.bailCode { return nil }
            out.append(contentsOf: UnsafeBufferPointer(start: base + runStart, count: i - runStart))
            let offset = Int(c >> 8), count = Int(c & 0xFF)
            events.append(.init(f: out.count, r: i, flen: count, rlen: len))
            out.append(contentsOf: pool[offset..<(offset + count)])
            i += len
            runStart = i
        }
        out.append(contentsOf: UnsafeBufferPointer(start: base + runStart, count: n - runStart))
        // 大写转小写长度不变, 不影响位置映射。
        out.withUnsafeMutableBufferPointer { o in
            for k in upper { o[k] |= 0x20 }
        }
        return SearchFolded(bytes: out, events: events)
    }
}
