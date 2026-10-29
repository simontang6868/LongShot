import SwiftUI

/// 设置页：三条硬约束相关的开关都集中在这里，且都带默认值/可关闭说明。
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var clearedMsg: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("重叠量（默认 15%/15%，可调 0~40%）") {
                    HStack {
                        Text("顶部裁切")
                        Slider(value: $settings.topCropRatio, in: 0...0.40, step: 0.01)
                        Text("\(Int(settings.topCropRatio * 100))%").frame(width: 44)
                    }
                    HStack {
                        Text("底部裁切")
                        Slider(value: $settings.bottomCropRatio, in: 0...0.40, step: 0.01)
                        Text("\(Int(settings.bottomCropRatio * 100))%").frame(width: 44)
                    }
                }

                Section("智能推荐（默认开、可关）") {
                    Toggle("智能推荐总开关", isOn: $settings.advisorEnabled)
                    Toggle("拼接前检查重叠", isOn: $settings.checkOverlapBeforeStitch)
                }

                Section("接缝处理") {
                    Toggle("裁掉重复的状态栏/导航栏带", isOn: $settings.enableStatusBarCrop)
                    Toggle("裁掉横向黑/白边", isOn: $settings.enableEdgeCrop)
                }

                Section("导出") {
                    Picker("默认导出格式", selection: exportFormatBinding) {
                        Text("PNG").tag("png")
                        Text("JPEG").tag("jpeg")
                        Text("HEIC").tag("heic")
                        Text("PDF").tag("pdf")
                    }
                    Toggle("超高自动切片（>16000px）", isOn: $settings.sliceEnabled)
                    Stepper("每片高度 \(settings.sliceHeight)px", value: $settings.sliceHeight, in: 2000...16000, step: 1000)
                    Toggle("保留切片原件", isOn: $settings.keepOriginals)
                    Button("清空切片缓存") {
                        CacheManager.clearAll()
                        clearedMsg = "已清空 Library/Caches/Slices"
                    }
                }

                Section {
                    Text("本 App 全程离线、零网络：不联网、不上传、不埋点、不接任何带网络能力的 SDK，无服务器、无持续费用。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("隐私 / 网络") }
            }
            .navigationTitle("设置")
            .alert("提示", isPresented: Binding(get: { clearedMsg != nil }, set: { if !$0 { clearedMsg = nil } })) {
                Button("好") {}
            } message: { Text(clearedMsg ?? "") }
        }
    }

    private var exportFormatBinding: Binding<String> {
        Binding(get: { settings.exportFormatRaw }, set: { settings.exportFormatRaw = $0 })
    }
}
