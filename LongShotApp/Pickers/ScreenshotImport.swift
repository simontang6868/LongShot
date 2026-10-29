import PhotosUI
import SwiftUI
import UIKit

/// 通用 PHPicker 封装：不申请相册完整权限（iOS 14+ 无弹窗），我们只拿到图片副本。
/// Tab A、Tab B 共用。selectionLimit=0 表示多选不限。
struct PHPickerWrapper: UIViewControllerRepresentable {
    var filter: PHPickerFilter = .images
    var selectionLimit: Int = 0
    var onPicked: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration()
        cfg.filter = filter
        cfg.selectionLimit = selectionLimit
        cfg.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: cfg)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PHPickerWrapper
        init(_ p: PHPickerWrapper) { parent = p }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            var images: [UIImage] = []
            let group = DispatchGroup()
            for r in results {
                group.enter()
                r.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage { images.append(img) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.parent.onPicked(images)
            }
        }
    }
}

/// Tab A：连续截图拼（主打）。用户自己用系统截图（侧边+音量上），再来这里导入。
struct ScreenshotImportView: View {
    @State private var showPicker = false
    @State private var showGuide = false
    @State private var picked: [UIImage] = []
    @State private var navigate = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 顶部可折叠引导文案
                DisclosureGroup("怎么截？（点开看）") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. 打开要截长图的页面，截第一张（侧边键 + 音量上）")
                        Text("2. 往下滚一截，再截一张，让两张之间留 15%~20% 重叠")
                        Text("3. 回来点下方「导入截图」，按顺序选中它们")
                        Button("查看系统截图引导") { showGuide = true }
                            .font(.caption)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                Spacer()

                if picked.isEmpty {
                    EmptyStateView("还没有截图", systemImage: "photo.on.rectangle.angled",
                                   description: "截几张图后，点下方按钮导入")
                } else {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(Array(picked.enumerated()), id: \.offset) { i, img in
                                Image(uiImage: img)
                                    .resizable().scaledToFit().frame(height: 140)
                                    .overlay(alignment: .bottomLeading) {
                                        Text("\(i + 1)").foregroundStyle(.white)
                                            .padding(4).background(.black.opacity(0.6))
                                    }
                            }
                        }
                    }
                    NavigationLink("进入编辑页（\(picked.count) 张）", destination: EditorView(mode: .screenshot, images: picked))
                        .buttonStyle(.borderedProminent)
                }

                Button { showPicker = true } label: {
                    Label(picked.isEmpty ? "导入截图" : "再导入几张", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
            .navigationTitle("连续截图拼")
            .sheet(isPresented: $showPicker) {
                PHPickerWrapper(selectionLimit: 0) { imgs in
                    picked.append(contentsOf: imgs)
                    showPicker = false
                }
            }
            .sheet(isPresented: $showGuide) { ScreenshotGuideSheet() }
        }
    }
}

/// 系统截图引导：半屏提示页，教用户用系统截图手势。我们不复刻截图能力。
struct ScreenshotGuideSheet: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("用系统截图，最干净也最稳").font(.headline)
                    Text("• iPhone：同时按「侧边键 + 音量上键」截一张")
                    Text("• 截完会自动存到「照片」")
                    Text("• 回到本 App，点「导入截图」从照片里选中刚截的几张")
                    Text("• 往下滚一点再截下一张，让相邻两张留约 15%~20% 重叠，拼出来才不跳段")
                    Text("小提示：滚动永远靠你自己的手指 + 系统截图，本 App 不会也不申请屏幕录制权限。")
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("系统截图引导")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("知道了") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
