import CopyCore
import SwiftUI

/// The History pane's storage block: a total, a proportional stacked bar, per-type rows
/// (with a per-type "Clear"), and a prominent "Clear History" button. Reads
/// `ItemStore.storageBreakdown()` (the *clearable* set:
/// favorites and pinboard items are permanent and excluded) and clears through the store,
/// which the shelf observes live via GRDB, so an open shelf refreshes on its own.
struct StorageUsageSection: View {
    let store: ItemStore

    @State private var usage: [StorageUsage]

    /// 同步读一次统计, 设置窗口按内容高度定窗口大小, 首帧就要是最终高度。
    init(store: ItemStore) {
        self.store = store
        _usage = State(initialValue: (try? store.storageBreakdown()) ?? [])
    }
    @State private var confirmClearAll = false
    @State private var pendingKindClear: StorageCategory?

    var body: some View {
        // 不依赖 Form/Section: 设置窗口改成两栏排版后, 这块直接放在「存储：」右栏。
        VStack(alignment: .leading, spacing: 10) {
            if categories.isEmpty {
                Text("No clearable history")
                    .foregroundStyle(.secondary)
            } else {
                summary
                VStack(spacing: 6) {
                    ForEach(categories) { row($0) }
                }
                Button(role: .destructive) {
                    confirmClearAll = true
                } label: {
                    Text(String(localized: "Clear History…"))
                }
                .controlSize(.regular)
                .padding(.top, 2)
            }
            SettingsHelp(String(localized: "Favorites and pinboard items are kept and aren't counted here."))
        }
        .onAppear(perform: reload)
        .confirmationDialog(String(localized: "Clear clipboard history?"), isPresented: $confirmClearAll) {
            Button(String(localized: "Clear History"), role: .destructive) { clearAll() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("Favorites and pinboard items are kept. This cannot be undone.")
        }
        .confirmationDialog(
            pendingKindClear.map { String(format: String(localized: "Clear all %@ from history?"), $0.label.lowercased()) } ?? "",
            isPresented: pendingKindClearShown,
            presenting: pendingKindClear
        ) { category in
            Button(String(format: String(localized: "Clear %@"), category.label), role: .destructive) { clear(category: category) }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { _ in
            Text("Favorites and pinboard items are kept. This cannot be undone.")
        }
    }

    // MARK: Pieces

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                let itemText = totalCount == 1 ? String(localized: "%d item") : String(localized: "%d items")
                Text(String(format: itemText, totalCount))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(byteString(totalBytes))
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
            StackedBar(segments: categories.map { ($0.category.color, Double($0.bytes)) })
                .frame(height: 8)
        }
        .padding(.vertical, 4)
    }

    private func row(_ usage: CategoryUsage) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(usage.category.color)
                .frame(width: 10, height: 10)
            Text(usage.category.label)
            Spacer(minLength: 8)
            Text("\(usage.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(byteString(usage.bytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 62, alignment: .trailing)
            IconButton(systemName: "trash", fontSize: 11,
                       size: CGSize(width: 24, height: 22),
                       help: String(format: String(localized: "Clear %@"), usage.category.label)) {
                pendingKindClear = usage.category
            }
        }
    }

    // MARK: Data

    private var categories: [CategoryUsage] {
        let byKind = Dictionary(usage.map { ($0.kind, $0) }, uniquingKeysWith: { a, _ in a })
        return StorageCategory.allCases.compactMap { category in
            let rows = category.kinds.compactMap { byKind[$0] }
            let count = rows.reduce(0) { $0 + $1.count }
            let bytes = rows.reduce(0) { $0 + $1.bytes }
            guard count > 0 else { return nil }
            return CategoryUsage(category: category, count: count, bytes: bytes)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private var totalBytes: Int { categories.reduce(0) { $0 + $1.bytes } }
    private var totalCount: Int { categories.reduce(0) { $0 + $1.count } }

    private var pendingKindClearShown: Binding<Bool> {
        Binding(get: { pendingKindClear != nil }, set: { if !$0 { pendingKindClear = nil } })
    }

    private func reload() {
        usage = (try? store.storageBreakdown()) ?? []
    }

    private func clearAll() {
        try? store.clearHistory(keepFavorites: true)
        reload()
    }

    private func clear(category: StorageCategory) {
        for kind in category.kinds {
            try? store.clearHistory(kind: kind)
        }
        reload()
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// One aggregated display row: a category and its summed count/bytes.
private struct CategoryUsage: Identifiable {
    let category: StorageCategory
    let count: Int
    let bytes: Int
    var id: StorageCategory { category }
}

/// Display buckets for the storage breakdown, mirroring `ShelfScope`'s categories (Text
/// folds in rich text) with a distinct color per bucket.
enum StorageCategory: String, CaseIterable, Identifiable, Hashable {
    case text, links, images, files, colors

    var id: String { rawValue }

    var kinds: [ItemKind] {
        switch self {
        case .text: return [.text, .richText]
        case .links: return [.link]
        case .images: return [.image]
        case .files: return [.file]
        case .colors: return [.color]
        }
    }

    var label: String {
        switch self {
        case .text: return String(localized: "Text")
        case .links: return String(localized: "Links")
        case .images: return String(localized: "Images")
        case .files: return String(localized: "Files")
        case .colors: return String(localized: "Colors")
        }
    }

    var color: Color {
        switch self {
        case .text: return .blue
        case .links: return .teal
        case .images: return .orange
        case .files: return .green
        case .colors: return .purple
        }
    }
}

/// A slim horizontal bar split into proportional colored segments, clipped to a capsule.
struct StackedBar: View {
    let segments: [(color: Color, value: Double)]

    var body: some View {
        GeometryReader { geo in
            let total = max(segments.reduce(0) { $0 + $1.value }, 1)
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    segment.color
                        .frame(width: geo.size.width * segment.value / total)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(Capsule())
        .background(Capsule().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.4)))
    }
}
