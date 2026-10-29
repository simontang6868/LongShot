import SwiftUI

/// 历史列表：缩略图 + 拼接参数快照。点「套用参数」把当时的重叠量/开关写回设置。
/// 注：原始切片图默认清理（设置可保留），故「完整重新拼」依赖保留的原件，这里提供参数回灌。
struct HistoryView: View {
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        NavigationStack {
            List {
                if history.records.isEmpty {
                    EmptyStateView("还没有历史", systemImage: "clock", description: "拼完一次会长这里")
                }
                ForEach(history.records) { rec in
                    HStack {
                        if let img = UIImage(data: rec.thumbnailPNG) {
                            Image(uiImage: img).resizable().scaledToFit().frame(width: 60, height: 80)
                                .cornerRadius(6)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rec.mode == .screenshot ? "连续截图拼" : "相册选图拼")
                                .font(.headline)
                            Text("重叠 \(Int(rec.topCropRatio * 100))% / \(Int(rec.bottomCropRatio * 100))% · 推荐\(rec.advisorEnabled ? "开" : "关")")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(rec.sliceCount) 张\(rec.sliced ? "（已切片）" : "") · \(rec.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("套用参数") {
                            settings.cropParams = CropParams(topCropRatio: CGFloat(rec.topCropRatio),
                                                             bottomCropRatio: CGFloat(rec.bottomCropRatio))
                            settings.advisorEnabled = rec.advisorEnabled
                        }
                        .font(.caption)
                    }
                }
                .onDelete { idx in
                    idx.map { history.records[$0].id }.forEach { history.remove($0) }
                }
            }
            .navigationTitle("历史")
        }
    }
}
