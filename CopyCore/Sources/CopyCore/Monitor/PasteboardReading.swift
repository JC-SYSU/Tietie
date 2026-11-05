import AppKit

public protocol PasteboardReading {
    var changeCount: Int { get }
    func typeIdentifiers() -> [String]
    func data(forUTI uti: String) -> Data?
    func string() -> String?
    func fileURLs() -> [URL]
    func colorHex() -> String?
}

extension NSPasteboard: PasteboardReading {
    public func typeIdentifiers() -> [String] {
        (types ?? []).map(\.rawValue)
    }

    public func data(forUTI uti: String) -> Data? {
        data(forType: NSPasteboard.PasteboardType(uti))
    }

    public func string() -> String? {
        string(forType: .string)
    }

    public func fileURLs() -> [URL] {
        (readObjects(forClasses: [NSURL.self],
                     options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    public func colorHex() -> String? {
        guard let color = (readObjects(forClasses: [NSColor.self]) as? [NSColor])?.first,
              let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int(round(srgb.redComponent * 255)),
                      Int(round(srgb.greenComponent * 255)),
                      Int(round(srgb.blueComponent * 255)))
    }
}

/// 「同时改写系统剪贴板」模式用: 读出剪贴板上唯一那一项的全部类型, 再整体替换。
public protocol PasteboardRewriting: AnyObject {
    /// 剪贴板上恰好一项、不含文件、所有类型都读得出且总量不超上限时, 返回该项全部类型;
    /// 否则 nil (不改写)。`optionalTypes` 读不出数据时跳过, 其余类型读不出就放弃。
    func singleItemRepresentations(optionalTypes: Set<String>, maxTotalBytes: Int) -> [CapturedRepresentation]?
    /// 清空剪贴板, 写入一项; 返回写入后的 changeCount。
    func replaceContents(with representations: [CapturedRepresentation]) -> Int
}

extension NSPasteboard: PasteboardRewriting {
    public func singleItemRepresentations(optionalTypes: Set<String>,
                                          maxTotalBytes: Int) -> [CapturedRepresentation]? {
        guard let items = pasteboardItems, items.count == 1 else { return nil }
        let types = items[0].types.map(\.rawValue)
        // 文件和文件承诺 (拖放/Finder) 不碰。
        let fileTypes: Set<String> = ["public.file-url", "com.apple.pasteboard.promised-file-url",
                                      "com.apple.NSFilePromiseItemMetaData"]
        guard !types.contains(where: fileTypes.contains) else { return nil }
        var reps: [CapturedRepresentation] = []
        var total = 0
        for type in types {
            guard let data = items[0].data(forType: NSPasteboard.PasteboardType(type)) else {
                if optionalTypes.contains(type) { continue }
                return nil
            }
            total += data.count
            guard total <= maxTotalBytes else { return nil }
            reps.append(CapturedRepresentation(uti: type, data: data))
        }
        return reps
    }

    public func replaceContents(with representations: [CapturedRepresentation]) -> Int {
        clearContents()
        let item = NSPasteboardItem()
        for rep in representations {
            item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.uti))
        }
        writeObjects([item])
        return changeCount
    }
}
