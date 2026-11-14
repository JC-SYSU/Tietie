import AppKit

public protocol PasteboardWriting {
    func write(_ representations: [CapturedRepresentation], marker: String)
}

public protocol KeyEventPosting {
    func postCommandV()
}

extension NSPasteboard: PasteboardWriting {
    public func write(_ representations: [CapturedRepresentation], marker: String) {
        clearContents()

        // 只有文件 (文件条目) 时按文件写, 系统会给每个文件补上文件名等类型。图片条目同时带
        // 图片数据、文件 URL 和路径文本, 走下面的单个 item, 几种格式都保留。
        let urls = representations
            .filter { $0.uti == "public.file-url" }
            .compactMap { URL(dataRepresentation: $0.data, relativeTo: nil) }
        if !urls.isEmpty, representations.allSatisfy({ $0.uti == "public.file-url" }) {
            writeObjects(urls as [NSURL])
            setData(Data(), forType: NSPasteboard.PasteboardType(marker))
            return
        }

        let item = NSPasteboardItem()
        for rep in representations {
            item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.uti))
        }
        item.setData(Data(), forType: NSPasteboard.PasteboardType(marker))
        writeObjects([item])
    }
}

public struct CGKeyEventPoster: KeyEventPosting {
    public init() {}

    public func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // kVK_ANSI_V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        // Mark as Copy's own synthesized keystroke so the Paste Stack's CGEvent tap
        // (which watches for a *user-initiated* plain ⌘V) lets this one straight
        // through instead of hijacking it as a "walk the queue" request.
        keyDown?.setIntegerValueField(.eventSourceUserData, value: CopyPasteboard.selfEventUserData)
        keyUp?.setIntegerValueField(.eventSourceUserData, value: CopyPasteboard.selfEventUserData)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

public final class PasteService {
    private let pasteboard: PasteboardWriting
    private let keyPoster: KeyEventPosting

    public init(pasteboard: PasteboardWriting, keyPoster: KeyEventPosting) {
        self.pasteboard = pasteboard
        self.keyPoster = keyPoster
    }

    public func place(_ representations: [CapturedRepresentation], plainTextOnly: Bool) {
        // 改动前入库的旧条目可能还带着末尾换行, 粘贴时统一去掉。
        var reps = TrailingNewlines.strip(representations) ?? representations
        if plainTextOnly,
           let plain = reps.first(where: { $0.uti == "public.utf8-plain-text" }) {
            reps = [plain]
        }
        pasteboard.write(reps, marker: CopyPasteboard.selfMarkerType)
    }

    public func sendPasteKeystroke() {
        keyPoster.postCommandV()
    }
}
